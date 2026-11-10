import Foundation
import Testing
@testable import AwakerCore

@Suite struct SessionStatsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func awakeTimeClipsSessionsToTheWindow() {
        let session = Session(start: date(10, 9), end: date(10, 12), trigger: .manual)
        let stats = SessionStats(sessions: [session], now: date(10, 18), calendar: calendar)

        #expect(stats.awakeTime(from: date(10, 10), to: date(10, 11)) == 3_600)
        #expect(stats.awakeTime(from: date(10, 13), to: date(10, 14)) == 0)
    }

    @Test func runningSessionCountsUntilNow() {
        let session = Session(start: date(10, 9), trigger: .claude)
        let stats = SessionStats(sessions: [session], now: date(10, 10, 30), calendar: calendar)

        #expect(stats.total == 5_400)
        #expect(stats.awakeTime(from: .distantPast, to: date(10, 10, 30), trigger: .manual) == 0)
    }

    @Test func daysSplitASessionAcrossMidnight() {
        let session = Session(start: date(9, 23), end: date(10, 1), trigger: .claude)
        let stats = SessionStats(sessions: [session], now: date(10, 12), calendar: calendar)
        let days = stats.days(2)

        #expect(days.count == 2)
        #expect(days[0].auto == 3_600)
        #expect(days[1].auto == 3_600)
        #expect(days[1].manual == 0)
    }

    @Test func weekOverWeekNeedsABaseline() {
        let recent = Session(start: date(9, 10), end: date(9, 12), trigger: .manual)
        #expect(SessionStats(sessions: [recent], now: date(10, 12), calendar: calendar).weekOverWeekChange == nil)

        let older = Session(start: date(1, 10), end: date(1, 11), trigger: .manual)
        let change = SessionStats(sessions: [recent, older], now: date(10, 12), calendar: calendar).weekOverWeekChange
        #expect(change == 1)
    }

    @Test func drainIgnoresShortAndChargingSessions() {
        let draining = Session(start: date(10, 8), end: date(10, 10), trigger: .manual, startBattery: 90, endBattery: 70)
        let charging = Session(start: date(10, 11), end: date(10, 12), trigger: .manual, startBattery: 40, endBattery: 60)
        let short = Session(start: date(10, 13), end: date(10, 13, 5), trigger: .manual, startBattery: 50, endBattery: 40)
        let stats = SessionStats(sessions: [draining, charging, short], now: date(10, 18), calendar: calendar)

        #expect(stats.drainPerHour == 10)
    }
}

@Suite struct SampleSeriesTests {
    @Test func batteryIsAveragedPerBucketAndSplitOnGaps() {
        let start = Date(timeIntervalSince1970: 600 * 1_000)
        let samples = [
            Sample(date: start, battery: 80, onAC: false, active: true, claudeSessions: 1),
            Sample(date: start.addingTimeInterval(60), battery: 79, onAC: false, active: true, claudeSessions: 1),
            Sample(date: start.addingTimeInterval(7_200), battery: 70, onAC: false, active: true, claudeSessions: 1),
        ]
        let points = SampleSeries.battery(samples)

        #expect(points.count == 2)
        #expect(points[0].value == 79.5)
        #expect(points[0].segment != points[1].segment)
    }

    @Test func hourTicksStopBeforeTheEdge() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 0).addingTimeInterval(30 * 60)
        let ticks = SampleSeries.hourTicks(in: start...start.addingTimeInterval(6 * 3_600), every: 3, calendar: calendar)

        #expect(ticks.map { calendar.component(.hour, from: $0) } == [3])
    }
}

@Suite struct FormatTests {
    @Test func durations() {
        #expect(Format.duration(59) == "0 min")
        #expect(Format.duration(45 * 60) == "45 min")
        #expect(Format.duration(2 * 3_600 + 5 * 60) == "2 h 05")
        #expect(Format.clock(65 * 60) == "1:05")
    }
}
