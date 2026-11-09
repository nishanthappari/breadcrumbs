import Foundation

/// What a single box in a sprint ended up as.
public enum BoxState: String, Codable, Equatable, Sendable {
    case pending
    case worked
    case missed
}

/// Configuration a sprint is started with. Captured at start so changing
/// settings mid-sprint never alters the sprint in flight.
public struct SprintConfig: Equatable, Sendable {
    public var intervalSeconds: TimeInterval
    public var boxes: Int

    public init(intervalSeconds: TimeInterval, boxes: Int) {
        self.intervalSeconds = max(1, intervalSeconds)
        self.boxes = max(1, boxes)
    }
}

/// The engine's phase. Pure value, driven entirely by the caller's clock.
public enum SprintPhase: Equatable, Sendable {
    /// No sprint, or the last one was cancelled.
    case idle
    /// The current box's interval is counting down.
    case running(endsAt: Date)
    /// The current box is paused with `remaining` seconds left on it.
    case paused(remaining: TimeInterval)
    /// The current box's interval ended; waiting for "Did you work?".
    case awaitingCheckIn(intervalEndedAt: Date)
    /// Every box has been answered.
    case completed
}

public struct Sprint: Equatable, Sendable {
    public let id: UUID
    public let config: SprintConfig
    public let startedAt: Date
    public internal(set) var boxes: [BoxState]
    /// Index of the box currently being worked / checked in. Equals `boxes.count` once complete.
    public internal(set) var currentIndex: Int

    public var workedCount: Int { boxes.filter { $0 == .worked }.count }
    public var answeredCount: Int { boxes.filter { $0 != .pending }.count }
}

/// One answered box, as written to the history log.
public struct BoxRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// When the box was answered.
    public var timestamp: Date
    public var worked: Bool
    public var sprintID: UUID
    public var boxIndex: Int
    public var intervalSeconds: TimeInterval
    /// When the interval actually ran out (the check-in appeared).
    public var intervalEndedAt: Date?

    public init(id: UUID = UUID(), timestamp: Date, worked: Bool, sprintID: UUID,
                boxIndex: Int, intervalSeconds: TimeInterval, intervalEndedAt: Date? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.worked = worked
        self.sprintID = sprintID
        self.boxIndex = boxIndex
        self.intervalSeconds = intervalSeconds
        self.intervalEndedAt = intervalEndedAt
    }
}

/// The sprint state machine.
///
///     idle ──start──▶ running ──tick(≥endsAt)──▶ awaitingCheckIn ──answer──▶ running (next box)
///                      ▲  │                                        └─answer(last)──▶ completed
///                 resume  pause
///                      │  ▼
///                     paused
///     any active phase ──cancel──▶ idle
///
/// The next box only starts when the check-in is answered, so time away from
/// the desk never counts toward an interval.
public struct SprintEngine: Equatable, Sendable {
    public private(set) var phase: SprintPhase = .idle
    public private(set) var sprint: Sprint?

    public init() {}

    /// True while a sprint is running, paused or waiting for a check-in.
    public var isActive: Bool {
        switch phase {
        case .running, .paused, .awaitingCheckIn: return true
        case .idle, .completed: return false
        }
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    public var isAwaitingCheckIn: Bool {
        if case .awaitingCheckIn = phase { return true }
        return false
    }

    /// Starts a new sprint. Ignored (returns false) while one is already active.
    @discardableResult
    public mutating func start(config: SprintConfig, now: Date, id: UUID = UUID()) -> Bool {
        guard !isActive else { return false }
        sprint = Sprint(id: id, config: config, startedAt: now,
                        boxes: Array(repeating: .pending, count: config.boxes), currentIndex: 0)
        phase = .running(endsAt: now.addingTimeInterval(config.intervalSeconds))
        return true
    }

    /// Advances time. Returns true exactly when this call moved the sprint into a check-in.
    @discardableResult
    public mutating func tick(now: Date) -> Bool {
        guard case let .running(endsAt) = phase, now >= endsAt else { return false }
        phase = .awaitingCheckIn(intervalEndedAt: endsAt)
        return true
    }

    /// Seconds left on the current box (running or paused), nil otherwise.
    public func remaining(now: Date) -> TimeInterval? {
        switch phase {
        case let .running(endsAt): return max(0, endsAt.timeIntervalSince(now))
        case let .paused(remaining): return remaining
        default: return nil
        }
    }

    /// 0…1 progress through the current box's interval.
    public func progress(now: Date) -> Double {
        guard let sprint else { return 0 }
        switch phase {
        case .awaitingCheckIn: return 1
        case .running, .paused:
            let total = sprint.config.intervalSeconds
            let left = remaining(now: now) ?? total
            return min(1, max(0, 1 - left / total))
        default: return 0
        }
    }

    @discardableResult
    public mutating func pause(now: Date) -> Bool {
        guard case let .running(endsAt) = phase else { return false }
        let left = endsAt.timeIntervalSince(now)
        if left <= 0 {
            // The interval already ran out; it's a check-in, not a pause.
            phase = .awaitingCheckIn(intervalEndedAt: endsAt)
            return false
        }
        phase = .paused(remaining: left)
        return true
    }

    @discardableResult
    public mutating func resume(now: Date) -> Bool {
        guard case let .paused(remaining) = phase else { return false }
        phase = .running(endsAt: now.addingTimeInterval(remaining))
        return true
    }

    @discardableResult
    public mutating func togglePause(now: Date) -> Bool {
        isPaused ? resume(now: now) : pause(now: now)
    }

    /// Answers "Did you work?" for the current box. Returns the record to log, or nil if
    /// there was no check-in pending. Starts the next box immediately, or completes the sprint.
    @discardableResult
    public mutating func answer(worked: Bool, now: Date) -> BoxRecord? {
        guard case let .awaitingCheckIn(endedAt) = phase, var s = sprint else { return nil }
        let index = s.currentIndex
        s.boxes[index] = worked ? .worked : .missed
        s.currentIndex = index + 1
        sprint = s
        let record = BoxRecord(timestamp: now, worked: worked, sprintID: s.id, boxIndex: index,
                               intervalSeconds: s.config.intervalSeconds, intervalEndedAt: endedAt)
        if s.currentIndex >= s.config.boxes {
            phase = .completed
        } else {
            phase = .running(endsAt: now.addingTimeInterval(s.config.intervalSeconds))
        }
        return record
    }

    /// Cancels the active sprint. Boxes already answered stay in history; the box in
    /// progress is discarded. Returns false if nothing was active.
    @discardableResult
    public mutating func cancel() -> Bool {
        guard isActive else { return false }
        phase = .idle
        sprint = nil
        return true
    }

    /// Clears a completed sprint back to idle (e.g. after the completion screen is dismissed).
    public mutating func reset() {
        guard !isActive else { return }
        phase = .idle
        sprint = nil
    }
}
