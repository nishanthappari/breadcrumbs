import AppKit
import BreadcrumbsCore
import Combine
import SwiftUI

/// Owns the timer. The engine is pure; this class supplies the clock, persists answers,
/// plays the chime and tells the window layer what happened.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var engine = SprintEngine()
    @Published private(set) var now = Date()
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

    var onIntervalEnded: (() -> Void)?
    var onAnswered: ((_ worked: Bool, _ completed: Bool) -> Void)?
    var onSprintStarted: (() -> Void)?
    var onCancelled: (() -> Void)?
    var hotKeyRegistered = false

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
        now = t
        startFastTimer()
        onSprintStarted?()
        writeStatus()
    }

    func togglePause() {
        let t = Date()
        guard engine.isActive else { return }
        engine.togglePause(now: t)
        now = t
        if engine.isAwaitingCheckIn { intervalEnded() }
        writeStatus()
    }

    func pause() { if case .running = engine.phase { togglePause() } }
    func resume() { if engine.isPaused { togglePause() } }

    func answer(worked: Bool) {
        let t = Date()
        guard let record = engine.answer(worked: worked, now: t) else { return }
        now = t
        do { try history.append(record) } catch { NSLog("Breadcrumbs: failed to write history: \(error)") }
        refreshStats()
        let completed = engine.phase == .completed
        if completed {
            lastSprint = engine.sprint
            stopFastTimer()
        }
        onAnswered?(worked, completed)
        writeStatus()
    }

    func cancel() {
        guard engine.cancel() else { return }
        stopFastTimer()
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

    private func startFastTimer() {
        stopFastTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        fastTimer = timer
    }

    private func stopFastTimer() {
        fastTimer?.invalidate()
        fastTimer = nil
    }

    private func tick() {
        guard engine.isActive else { return }
        now = Date()
        var e = engine
        if e.tick(now: now) {
            engine = e
            intervalEnded()
        }
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
        self.now = now
        self.lastSprint = lastSprint
    }
}
