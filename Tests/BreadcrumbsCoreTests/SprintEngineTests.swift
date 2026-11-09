import Foundation
import Testing
@testable import BreadcrumbsCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Suite("Sprint state machine")
struct SprintEngineTests {
    let config = SprintConfig(intervalSeconds: 300, boxes: 3)

    @Test func startBeginsFirstBoxImmediately() {
        var e = SprintEngine()
        #expect(e.phase == .idle)
        do { let r = e.start(config: config, now: t0); #expect(r) }
        #expect(e.phase == .running(endsAt: at(300)))
        #expect(e.sprint?.currentIndex == 0)
        #expect(e.sprint?.boxes == [.pending, .pending, .pending])
        #expect(e.remaining(now: at(60)) == 240)
    }

    @Test func intervalEndTriggersCheckInExactlyOnce() {
        var e = SprintEngine()
        e.start(config: config, now: t0)
        do { let r = e.tick(now: at(299)); #expect(r == false) }
        #expect(e.isAwaitingCheckIn == false)
        do { let r = e.tick(now: at(300)); #expect(r == true) }
        #expect(e.phase == .awaitingCheckIn(intervalEndedAt: at(300)))
        do { let r = e.tick(now: at(400)); #expect(r == false, "already checking in; no second trigger") }
    }

    @Test func noTimeCountsWhileWaitingForAnswer() {
        var e = SprintEngine()
        e.start(config: config, now: t0)
        e.tick(now: at(300))
        // Away from the desk for 20 minutes before answering.
        let rec = e.answer(worked: true, now: at(1500))
        #expect(rec?.worked == true)
        #expect(rec?.boxIndex == 0)
        #expect(rec?.intervalEndedAt == at(300))
        #expect(e.phase == .running(endsAt: at(1800)), "next box starts at answer time")
    }

    @Test func yesAndNoMarkBoxesAndAdvance() {
        var e = SprintEngine()
        e.start(config: config, now: t0)
        e.tick(now: at(300)); e.answer(worked: true, now: at(300))
        #expect(e.sprint?.boxes == [.worked, .pending, .pending])
        #expect(e.sprint?.currentIndex == 1)
        e.tick(now: at(600)); e.answer(worked: false, now: at(600))
        #expect(e.sprint?.boxes == [.worked, .missed, .pending])
        #expect(e.sprint?.currentIndex == 2)
        #expect(e.isActive)
    }

    @Test func sprintCompletesAfterNBoxesAndDoesNotRestart() {
        var e = SprintEngine()
        e.start(config: config, now: t0)
        var records: [BoxRecord] = []
        var now = t0
        for i in 0..<3 {
            now = now.addingTimeInterval(300)
            do { let r = e.tick(now: now); #expect(r) }
            if let r = e.answer(worked: i != 1, now: now) { records.append(r) }
        }
        #expect(e.phase == .completed)
        #expect(e.isActive == false)
        #expect(e.sprint?.workedCount == 2)
        #expect(e.sprint?.answeredCount == 3)
        #expect(records.map(\.boxIndex) == [0, 1, 2])
        #expect(Set(records.map(\.sprintID)).count == 1)
        // Nothing restarts on its own.
        do { let r = e.tick(now: now.addingTimeInterval(10_000)); #expect(r == false) }
        #expect(e.phase == .completed)
    }

    @Test func answerWithoutCheckInIsIgnored() {
        var e = SprintEngine()
        do { let r = e.answer(worked: true, now: t0); #expect(r == nil) }
        e.start(config: config, now: t0)
        do { let r = e.answer(worked: true, now: at(10)); #expect(r == nil) }
        #expect(e.sprint?.boxes == [.pending, .pending, .pending])
    }

    @Test func pauseFreezesRemainingAndResumeContinues() {
        var e = SprintEngine()
        e.start(config: config, now: t0)
        do { let r = e.pause(now: at(100)); #expect(r) }
        #expect(e.phase == .paused(remaining: 200))
        #expect(e.isPaused)
        // A long pause: ticks do nothing, remaining does not move.
        do { let r = e.tick(now: at(5000)); #expect(r == false) }
        #expect(e.remaining(now: at(5000)) == 200)
        do { let r = e.resume(now: at(5000)); #expect(r) }
        #expect(e.phase == .running(endsAt: at(5200)))
        do { let r = e.tick(now: at(5199)); #expect(r == false) }
        do { let r = e.tick(now: at(5200)); #expect(r == true) }
    }

    @Test func togglePause() {
        var e = SprintEngine()
        e.start(config: config, now: t0)
        e.togglePause(now: at(50))
        #expect(e.isPaused)
        e.togglePause(now: at(60))
        #expect(e.phase == .running(endsAt: at(310)))
    }

    @Test func pauseAfterIntervalRanOutBecomesCheckIn() {
        var e = SprintEngine()
        e.start(config: config, now: t0)
        do { let r = e.pause(now: at(301)); #expect(r == false) }
        #expect(e.isAwaitingCheckIn)
    }

    @Test func pauseAndResumeAreNoOpsOutsideTheirPhase() {
        var e = SprintEngine()
        do { let r = e.pause(now: t0); #expect(r == false) }
        do { let r = e.resume(now: t0); #expect(r == false) }
        e.start(config: config, now: t0)
        do { let r = e.resume(now: at(1)); #expect(r == false) }
        e.tick(now: at(300))
        do { let r = e.pause(now: at(301)); #expect(r == false) }
        #expect(e.isAwaitingCheckIn)
    }

    @Test func cancelFromEveryActivePhase() {
        for setup in 0..<3 {
            var e = SprintEngine()
            e.start(config: config, now: t0)
            if setup == 1 { e.pause(now: at(10)) }
            if setup == 2 { e.tick(now: at(300)) }
            do { let r = e.cancel(); #expect(r) }
            #expect(e.phase == .idle)
            #expect(e.sprint == nil)
        }
        var idle = SprintEngine()
        do { let r = idle.cancel(); #expect(r == false) }
    }

    @Test func cannotStartWhileActiveButCanAfterCompletionOrCancel() {
        var e = SprintEngine()
        e.start(config: SprintConfig(intervalSeconds: 10, boxes: 1), now: t0)
        let firstID = e.sprint?.id
        do { let r = e.start(config: config, now: at(1)); #expect(r == false) }
        #expect(e.sprint?.id == firstID)
        e.tick(now: at(10)); e.answer(worked: true, now: at(10))
        #expect(e.phase == .completed)
        do { let r = e.start(config: config, now: at(20)); #expect(r) }
        #expect(e.sprint?.id != firstID)
        e.cancel()
        do { let r = e.start(config: config, now: at(30)); #expect(r) }
    }

    @Test func progressRisesThroughTheInterval() {
        var e = SprintEngine()
        e.start(config: config, now: t0)
        #expect(e.progress(now: t0) == 0)
        #expect(abs(e.progress(now: at(150)) - 0.5) < 1e-9)
        e.tick(now: at(300))
        #expect(e.progress(now: at(300)) == 1)
    }

    @Test func configClampsToAtLeastOne() {
        let c = SprintConfig(intervalSeconds: 0, boxes: 0)
        #expect(c.intervalSeconds == 1)
        #expect(c.boxes == 1)
    }
}

@Suite("Settings persistence")
struct SettingsTests {
    func freshDefaults() -> (UserDefaults, String) {
        let name = "breadcrumbs.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func defaultsAreFiveMinutesSixBoxes() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        let s = SettingsStore(defaults: d)
        #expect(s.intervalMinutes == 5)
        #expect(s.boxesPerSprint == 6)
        #expect(s.sprintConfig == SprintConfig(intervalSeconds: 300, boxes: 6))
    }

    @Test func valuesPersistAcrossInstances() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        let a = SettingsStore(defaults: d)
        a.intervalMinutes = 25
        a.boxesPerSprint = 4
        let b = SettingsStore(defaults: UserDefaults(suiteName: name)!)
        #expect(b.intervalMinutes == 25)
        #expect(b.boxesPerSprint == 4)
        #expect(b.sprintConfig == SprintConfig(intervalSeconds: 1500, boxes: 4))
    }

    @Test(arguments: [(0, 1), (1, 1), (60, 60), (61, 60), (-5, 1), (37, 37)])
    func intervalAcceptsOneToSixty(input: Int, expected: Int) {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        let s = SettingsStore(defaults: d)
        s.intervalMinutes = input
        #expect(s.intervalMinutes == expected)
    }

    @Test func boxesClampAndResetToDefaults() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        let s = SettingsStore(defaults: d)
        s.boxesPerSprint = 0
        #expect(s.boxesPerSprint == 1)
        s.boxesPerSprint = 99
        #expect(s.boxesPerSprint == 24)
        s.intervalMinutes = 42
        s.resetToDefaults()
        #expect(s.intervalMinutes == 5)
        #expect(s.boxesPerSprint == 6)
    }
}

@Suite("History log")
struct HistoryTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("breadcrumbs-tests-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
    }

    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func appendWritesJSONAndReloads() throws {
        let url = tempURL()
        let store = HistoryStore(fileURL: url, calendar: cal)
        let sid = UUID()
        try store.append(BoxRecord(timestamp: t0, worked: true, sprintID: sid, boxIndex: 0, intervalSeconds: 300))
        try store.append(BoxRecord(timestamp: at(300), worked: false, sprintID: sid, boxIndex: 1, intervalSeconds: 300))
        let reloaded = HistoryStore(fileURL: url, calendar: cal)
        #expect(reloaded.entries.count == 2)
        #expect(reloaded.entries.map(\.worked) == [true, false])
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"worked\" : true"))
        #expect(raw.contains("\"timestamp\""))
    }

    @Test func todayCountAndSevenDayStats() throws {
        let store = HistoryStore(fileURL: tempURL(), calendar: cal)
        let day: TimeInterval = 86_400
        let now = t0
        let sid = UUID()
        func add(_ offset: TimeInterval, _ worked: Bool) throws {
            try store.append(BoxRecord(timestamp: now.addingTimeInterval(offset), worked: worked,
                                       sprintID: sid, boxIndex: 0, intervalSeconds: 300))
        }
        try add(0, true); try add(-60, true); try add(-120, false)   // today: 2 worked, 1 missed
        try add(-2 * day, true)                                         // two days ago
        try add(-10 * day, true)                                        // outside the window
        #expect(store.workedToday(now: now) == 2)
        let week = store.lastDays(7, now: now)
        #expect(week.count == 7)
        #expect(week.last?.worked == 2)
        #expect(week.last?.missed == 1)
        #expect(week[4].worked == 1)
        #expect(week.map(\.total).reduce(0, +) == 4)
    }

    @Test func corruptFileIsBackedUpNotLost() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let store = HistoryStore(fileURL: url, calendar: cal)
        #expect(store.entries.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(files.contains { $0.contains("corrupt") })
    }

    @Test func engineRecordsFlowIntoHistory() throws {
        let store = HistoryStore(fileURL: tempURL(), calendar: cal)
        var e = SprintEngine()
        e.start(config: SprintConfig(intervalSeconds: 10, boxes: 3), now: t0)
        for (i, worked) in [true, false, true].enumerated() {
            let t = at(Double(i + 1) * 10)
            e.tick(now: t)
            if let r = e.answer(worked: worked, now: t) { try store.append(r) }
        }
        #expect(e.phase == .completed)
        #expect(store.entries.count == 3)
        #expect(store.workedToday(now: at(30)) == 2)
    }
}
