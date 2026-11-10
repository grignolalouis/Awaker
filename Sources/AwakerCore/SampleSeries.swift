import Foundation

/// A chart-ready point. `segment` changes across gaps (Mac asleep, app closed) so lines don't bridge them.
public struct SeriesPoint: Identifiable, Sendable, Equatable {
    public let date: Date
    public let value: Double
    public let segment: Int

    public var id: Date { date }
}

public enum SampleSeries {
    /// Averages battery readings per bucket. Readings are whole percents, so raw data looks like stairs.
    public static func battery(_ samples: [Sample], bucket: TimeInterval = 600, maxGap: TimeInterval = 1_200) -> [SeriesPoint] {
        let buckets = Dictionary(grouping: samples.filter { $0.battery != nil }) {
            floor($0.date.timeIntervalSince1970 / bucket)
        }
        let averaged = buckets.keys.sorted().map { key -> (Date, Double) in
            let readings = buckets[key, default: []].compactMap(\.battery)
            let mean = Double(readings.reduce(0, +)) / Double(readings.count)
            return (Date(timeIntervalSince1970: key * bucket + bucket / 2), mean)
        }
        return segmented(averaged, maxGap: maxGap)
    }

    /// Highest number of Claude Code sessions per bucket.
    public static func claudeSessions(_ samples: [Sample], bucket: TimeInterval = 3_600) -> [SeriesPoint] {
        let buckets = Dictionary(grouping: samples) { floor($0.date.timeIntervalSince1970 / bucket) }
        let peaks = buckets.keys.sorted().map { key -> (Date, Double) in
            let peak = buckets[key, default: []].map(\.claudeSessions).max() ?? 0
            return (Date(timeIntervalSince1970: key * bucket), Double(peak))
        }
        return segmented(peaks, maxGap: .infinity)
    }

    static func segmented(_ values: [(Date, Double)], maxGap: TimeInterval) -> [SeriesPoint] {
        var segment = 0
        var previous: Date?
        return values.map { date, value in
            if let previous, date.timeIntervalSince(previous) > maxGap { segment += 1 }
            previous = date
            return SeriesPoint(date: date, value: value, segment: segment)
        }
    }

    /// Whole hours that are multiples of `every`, stopping short of the end so axis labels never clip.
    public static func hourTicks(in range: ClosedRange<Date>, every: Int, calendar: Calendar = .current) -> [Date] {
        guard var tick = calendar.nextDate(after: range.lowerBound, matching: DateComponents(minute: 0),
                                           matchingPolicy: .nextTime) else { return [] }
        let limit = range.upperBound.addingTimeInterval(-Double(every) * 1_800)
        var ticks: [Date] = []
        while tick < limit {
            if calendar.component(.hour, from: tick) % every == 0 { ticks.append(tick) }
            tick.addTimeInterval(3_600)
        }
        return ticks
    }
}
