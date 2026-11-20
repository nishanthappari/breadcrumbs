import AppKit
import BreadcrumbsCore
import Combine
import SwiftUI

/// Owns the timer. The engine is pure; this class supplies the clock, persists answers,
/// plays the chime and tells the window layer what happened.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var engine = SprintEngine()
    @Published private(set) var todayWorked = 0
    @Published private(set) var todayMissed = 0
    @Published private(set) var week: [DayStat] = []
    @Published private(set) var intervalMinutes: Int
    @Published private(set) var boxesPerSprint: Int
    @Published private(set) var launchAtLogin: Bool = false
    /// The last completed sprint's tally, kept after the engine resets.
    @Published private(set) var lastSprint: Sprint?

    let settings: SettingsStore
    let history: HistoryStore
    let chime: Chime?
    let statusURL: URL?
    /// Ticks once per displayed second, and only while running. Kept out of the model's own
    /// `@Published` state so a tick doesn't re-render every view that observes the model.
    let clock = SprintClock()

    var onIntervalEnded: (() -> Void)?
    var onAnswered: ((_ worked: Bool, _ completed: Bool) -> Void)?
    var onSprintStarted: (() -> Void)?
    var onCancelled: (() -> Void)?
    var hotKeyRegistered = false
    /// Check-in shortcuts registered right now (empty unless a check-in is pending).
    var checkInHotKeys: [String] = []
    /// Check-in shortcuts that failed to register (taken by another app); the card hides them.
    var unavailableCheckInHotKeys: Set<String> = []

    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var wakeObserver: Any?

    init(settings: SettingsStore = SettingsStore(),
         history: HistoryStore = HistoryStore(),
         chime: Chime?,
         statusURL: URL? = HistoryStore.defaultURL.deletingLastPathComponent().appendingPathComponent("status.json")) {
        self.settings = settings
        self.history = history
        self.chime = chime
        self.statusURL = statusURL
        self.intervalMinutes = settings.intervalMinutes
        self.boxesPerSprint = settings.boxesPerSprint
        refreshStats()
    }

    /// Called once by the app on launch (not by snapshot fixtures).
    func activate() {
        launchAtLogin = LoginItem.isEnabled
        slowTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStats() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStats()
                self?.tick()
            }
        }
        writeStatus()
    }

    // MARK: Derived

    var now: Date { clock.now }
    var sprint: Sprint? { engine.sprint }
    var remaining: TimeInterval? { engine.remaining(now: now) }
    var progress: Double { engine.progress(now: now) }

    var currentMode: BoxView.Mode {
        switch engine.phase {
        case .running: return .running
        case .paused: return .paused
        case .awaitingCheckIn: return .awaiting
        default: return .still
        }
    }

    var nextConfig: SprintConfig { settings.sprintConfig }

    var menuBarText: String {
        switch engine.phase {
        case .running, .paused: return Format.clock(remaining ?? 0)
        case .awaitingCheckIn: return "Check in"
        case .idle, .completed: return "\(todayWorked)"
        }
    }

    // MARK: Actions

    func startSprint(override: SprintConfig? = nil) {
        if engine.phase == .completed { engine.reset() }
        let t = Date()
        guard engine.start(config: override ?? settings.sprintConfig, now: t) else { return }
        clock.set(t)
        syncFastTimer()
        onSprintStarted?()
        writeStatus()
    }

    func togglePause() {
        let t = Date()
        guard engine.isActive else { return }
        engine.togglePause(now: t)
        clock.set(t)
        syncFastTimer()
        if engine.isAwaitingCheckIn { intervalEnded() }
        writeStatus()
    }

    func pause() { if case .running = engine.phase { togglePause() } }
    func resume() { if engine.isPaused { togglePause() } }

    /// Answers the check-in. On the last box (both are ignored on any other box):
    /// `startNext` skips the completion card and starts a fresh sprint straight away;
    /// `stop` ends the sprint and closes the card, with no completion card either.
    func answer(worked: Bool, startNext: Bool = false, stop: Bool = false) {
        let t = Date()
        guard let record = engine.answer(worked: worked, now: t) else { return }
        clock.set(t)
        syncFastTimer()
        do { try history.append(record) } catch { NSLog("Breadcrumbs: failed to write history: \(error)") }
        refreshStats()
        let completed = engine.phase == .completed
        if completed {
            lastSprint = engine.sprint
        }
        if completed && startNext {
            // Show the brief "Ticked." beat, then let it fade; no completion card.
            onAnswered?(worked, false)
            startSprint()
            return
        }
        if completed && stop {
            // Same beat, then the card closes and the app goes back to idle.
            onAnswered?(worked, false)
            dismissCompletion()
            return
        }
        onAnswered?(worked, completed)
        writeStatus()
    }

    /// True while the check-in being asked is the sprint's final box.
    var isLastBoxCheckIn: Bool {
        guard engine.isAwaitingCheckIn, let s = engine.sprint else { return false }
        return s.currentIndex == s.config.boxes - 1
    }

    func cancel() {
        guard engine.cancel() else { return }
        syncFastTimer()
        onCancelled?()
        writeStatus()
    }

    func dismissCompletion() {
        engine.reset()
        writeStatus()
    }

    func setInterval(_ minutes: Int) {
        settings.intervalMinutes = minutes
        intervalMinutes = settings.intervalMinutes
        writeStatus()
    }

    func setBoxes(_ n: Int) {
        settings.boxesPerSprint = n
        boxesPerSprint = settings.boxesPerSprint
        writeStatus()
    }

    func resetSettings() {
        settings.resetToDefaults()
        intervalMinutes = settings.intervalMinutes
        boxesPerSprint = settings.boxesPerSprint
        writeStatus()
    }

    func setLaunchAtLogin(_ on: Bool) {
        LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
        writeStatus()
    }

    func refreshStats() {
        history.load()
        let today = history.stat(for: Date())
        todayWorked = today.worked
        todayMissed = today.missed
        week = history.lastDays(7)
    }

    // MARK: Clock

    /// Runs the timer only while a box is counting down. Paused, awaiting a check-in, idle and
    /// completed show nothing time-dependent, so they need no timer at all.
    private func syncFastTimer() {
        if case .running = engine.phase { scheduleNextTick() } else { stopFastTimer() }
    }

    /// One-shot timer for the instant the displayed second next changes — the countdown shows
    /// `ceil(remaining)`, so that's `endsAt - k` for whole `k`, and `k == 0` is the interval end.
    /// Re-armed from the wall clock on every fire, so sleep or a clock change self-corrects.
    private func scheduleNextTick() {
        stopFastTimer()
        guard case let .running(endsAt) = engine.phase else { return }
        let remaining = endsAt.timeIntervalSince(Date())
        let k = max(0, Self.displayedSeconds(remaining) - 1)
        // A hair past the boundary so the fire lands on the new second, never just before it.
        let fireAt = endsAt.addingTimeInterval(-Double(k) + 0.002)
        let timer = Timer(fire: fireAt, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Timers never fire early; tolerance only lets them fire late, which coalesces wakeups.
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        fastTimer = timer
    }

    private func stopFastTimer() {
        fastTimer?.invalidate()
        fastTimer = nil
    }

    /// Mirrors `Format.clock`'s rounding.
    private static func displayedSeconds(_ remaining: TimeInterval) -> Int {
        max(0, Int(remaining.rounded(.up)))
    }

    private func tick() {
        guard case let .running(endsAt) = engine.phase else { stopFastTimer(); return }
        let t = Date()
        var e = engine
        if e.tick(now: t) {
            engine = e
            clock.set(t)
            stopFastTimer()
            intervalEnded()
            return
        }
        // Publish only when what's on screen changes (the glyph's eighths step lands on the
        // next second at worst, as it did at the old 4 Hz to within 0.25 s).
        let shownBefore = Self.displayedSeconds(endsAt.timeIntervalSince(clock.now))
        if Self.displayedSeconds(endsAt.timeIntervalSince(t)) != shownBefore || clock.now > t {
            clock.set(t)
        }
        scheduleNextTick()
    }

    private func intervalEnded() {
        chime?.play()
        onIntervalEnded?()
        writeStatus()
    }

    // MARK: Status file (read by Raycast + the test harness)

    func writeStatus() {
        guard let statusURL else { return }
        let phase: String
        switch engine.phase {
        case .idle: phase = "idle"
        case .running: phase = "running"
        case .paused: phase = "paused"
        case .awaitingCheckIn: phase = "awaitingCheckIn"
        case .completed: phase = "completed"
        }
        var dict: [String: Any] = [
            "phase": phase,
            "todayWorked": todayWorked,
            "todayMissed": todayMissed,
            "intervalMinutes": intervalMinutes,
            "boxesPerSprint": boxesPerSprint,
            "launchAtLogin": launchAtLogin,
            "loginItemStatus": LoginItem.statusDescription,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "hotKeyRegistered": hotKeyRegistered,
            "checkInHotKeys": checkInHotKeys,
        ]
        if let s = engine.sprint {
            dict["boxes"] = s.boxes.map(\.rawValue)
            dict["currentBox"] = min(s.currentIndex + 1, s.config.boxes)
            dict["totalBoxes"] = s.config.boxes
            dict["intervalSeconds"] = s.config.intervalSeconds
        }
        if let r = engine.remaining(now: Date()) { dict["remainingSeconds"] = Int(r.rounded(.up)) }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: statusURL, options: .atomic)
    }

    // MARK: Fixtures (snapshot mode only)

    func debugLoad(engine: SprintEngine, now: Date, lastSprint: Sprint? = nil) {
        self.engine = engine
        clock.set(now)
        self.lastSprint = lastSprint
    }
}
