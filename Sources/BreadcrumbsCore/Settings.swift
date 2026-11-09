import Foundation

/// Persisted user settings, backed by UserDefaults.
public final class SettingsStore: @unchecked Sendable {
    public static let intervalRange = 1...60
    public static let boxesRange = 1...24
    public static let defaultIntervalMinutes = 5
    public static let defaultBoxes = 6

    enum Key {
        static let interval = "intervalMinutes"
        static let boxes = "boxesPerSprint"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Interval length in whole minutes, clamped to 1…60. Defaults to 5.
    public var intervalMinutes: Int {
        get {
            guard defaults.object(forKey: Key.interval) != nil else { return Self.defaultIntervalMinutes }
            return Self.clamp(defaults.integer(forKey: Key.interval), to: Self.intervalRange)
        }
        set { defaults.set(Self.clamp(newValue, to: Self.intervalRange), forKey: Key.interval) }
    }

    /// Boxes per sprint, clamped to 1…24. Defaults to 6.
    public var boxesPerSprint: Int {
        get {
            guard defaults.object(forKey: Key.boxes) != nil else { return Self.defaultBoxes }
            return Self.clamp(defaults.integer(forKey: Key.boxes), to: Self.boxesRange)
        }
        set { defaults.set(Self.clamp(newValue, to: Self.boxesRange), forKey: Key.boxes) }
    }

    public var sprintConfig: SprintConfig {
        SprintConfig(intervalSeconds: TimeInterval(intervalMinutes * 60), boxes: boxesPerSprint)
    }

    public func resetToDefaults() {
        intervalMinutes = Self.defaultIntervalMinutes
        boxesPerSprint = Self.defaultBoxes
    }

    static func clamp(_ v: Int, to r: ClosedRange<Int>) -> Int { min(r.upperBound, max(r.lowerBound, v)) }
}
