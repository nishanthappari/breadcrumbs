import Foundation

public struct DayStat: Equatable, Sendable, Identifiable {
    public var day: Date        // start of day
    public var worked: Int
    public var missed: Int
    public var id: Date { day }
    public var total: Int { worked + missed }
}

/// On-disk shape of `history.json`.
public struct HistoryFile: Codable, Equatable {
    public var version: Int = 1
    public var entries: [BoxRecord] = []
}

/// Append-only local log of every answered box, stored as JSON.
public final class HistoryStore: @unchecked Sendable {
    public let fileURL: URL
    public private(set) var entries: [BoxRecord] = []
    private let calendar: Calendar

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Breadcrumbs", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    public init(fileURL: URL = HistoryStore.defaultURL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        load()
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else { entries = []; return }
        if let file = try? Self.decoder.decode(HistoryFile.self, from: data) {
            entries = file.entries
        } else {
            // Unreadable file: keep a copy rather than silently overwriting it.
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            entries = []
        }
    }

    public func append(_ record: BoxRecord) throws {
        entries.append(record)
        try save()
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try Self.encoder.encode(HistoryFile(entries: entries))
        try data.write(to: fileURL, options: .atomic)
    }

    public func stat(for day: Date) -> DayStat {
        let start = calendar.startOfDay(for: day)
        let todays = entries.filter { calendar.isDate($0.timestamp, inSameDayAs: start) }
        let worked = todays.filter(\.worked).count
        return DayStat(day: start, worked: worked, missed: todays.count - worked)
    }

    public func workedToday(now: Date = Date()) -> Int { stat(for: now).worked }

    /// The last `days` days ending today, oldest first.
    public func lastDays(_ days: Int = 7, now: Date = Date()) -> [DayStat] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { stat(for: $0) }
        }
    }
}
