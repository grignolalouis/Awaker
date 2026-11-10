import SwiftUI

/// A timeline that ticks every `interval` seconds and not more often, or only once while paused.
///
/// SwiftUI's own `.animation(minimumInterval:)` schedule is driven by the display: the view graph was woken
/// on every screen refresh just to find that the interval had not passed yet. For a few frames per second,
/// a plain timer costs far less.
struct SteadySchedule: TimelineSchedule {
    let interval: TimeInterval
    var paused = false

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        guard !paused else { return AnySequence([startDate]) }
        let interval = interval
        return AnySequence(sequence(first: startDate) { $0.addingTimeInterval(interval) })
    }
}
