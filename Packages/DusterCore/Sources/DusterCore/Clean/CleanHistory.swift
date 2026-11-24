import Foundation

public struct CleanRecord: Sendable, Hashable {
    public let date: Date
    public let bytes: Int64
}

public struct WeeklyCleanTotal: Sendable, Hashable, Identifiable {
    public let weekStart: Date
    public let bytes: Int64

    public var id: Date { weekStart }
}

public struct CleanHistory: Sendable {
    public let records: [CleanRecord]

    public init(records: [CleanRecord]) {
        self.records = records
    }

    public init(logs: [CleanLog]) {
        records = logs.flatMap { $0.records() }
    }

    public var totalBytes: Int64 {
        records.reduce(0) { $0 + $1.bytes }
    }

    public var lastCleaned: Date? {
        records.map(\.date).max()
    }

    public func bytes(since start: Date) -> Int64 {
        records.filter { $0.date >= start }.reduce(0) { $0 + $1.bytes }
    }

    public func weeklyTotals(weeks: Int, now: Date = .now, calendar: Calendar = .current) -> [WeeklyCleanTotal] {
        guard weeks > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weeks).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let bytes = records.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.bytes }
            return WeeklyCleanTotal(weekStart: start, bytes: bytes)
        }
    }
}

extension CleanLog {
    public func records() -> [CleanRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4,
                  let date = try? Date(String(fields[0]), strategy: .iso8601),
                  let bytes = Int64(fields[2]) else { return nil }
            return CleanRecord(date: date, bytes: bytes)
        }
    }
}
