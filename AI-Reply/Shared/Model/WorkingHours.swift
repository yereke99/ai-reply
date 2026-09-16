import Foundation

/// A time of day, as minutes since midnight.
///
/// Stored as an integer rather than a `Date` on purpose. "10:00" is a wall-clock
/// fact about the user's week, not an instant; persisting a `Date` would bake in
/// whatever timezone and calendar date happened to be current when they set it,
/// and the schedule would quietly shift when they travelled.
struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    var minutes: Int

    init(minutes: Int) {
        self.minutes = min(max(minutes, 0), 24 * 60 - 1)
    }

    init(hour: Int, minute: Int) {
        self.init(minutes: hour * 60 + minute)
    }

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }

    /// 24-hour "HH:mm". Used both in the UI and in the model context, so the
    /// two can never disagree about what the user configured.
    var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// One day's availability. `weekday` follows `Calendar`'s convention where
/// Sunday is 1, so it can be compared against `Calendar.component(.weekday:)`
/// with no translation layer to get wrong.
struct DaySchedule: Codable, Hashable, Identifiable, Sendable {
    var weekday: Int
    var isEnabled: Bool
    var start: TimeOfDay
    var end: TimeOfDay

    var id: Int { weekday }

    /// Guards against a schedule that can never be inside itself.
    var isValid: Bool { isEnabled && start < end }
}

/// The user's optional working-hours configuration.
///
/// TIMEZONE. Everything is evaluated against `Calendar.current`, which follows
/// the device. No timezone is stored, no timezone is hard-coded, and the
/// backend is never told where the user is - only whether it is currently
/// inside their hours and when the next window opens.
struct WorkingHours: Codable, Hashable, Sendable {

    var isEnabled: Bool
    var days: [DaySchedule]

    /// Monday to Friday, 10:00-16:00, weekend off. Matches the brief's example
    /// and is a reasonable starting point that the user then edits.
    static let `default` = WorkingHours(
        isEnabled: false,
        days: (1...7).map { weekday in
            let isWeekday = weekday >= 2 && weekday <= 6
            return DaySchedule(
                weekday: weekday,
                isEnabled: isWeekday,
                start: TimeOfDay(hour: 10, minute: 0),
                end: TimeOfDay(hour: 16, minute: 0)
            )
        }
    )

    func schedule(for weekday: Int) -> DaySchedule? {
        days.first { $0.weekday == weekday }
    }

    // MARK: Derivation

    /// Everything the model needs to reason about time, and nothing more.
    ///
    /// Note what is absent: no timezone name, no city, no coordinates, no UTC
    /// offset. A wall-clock time and two booleans answer every question the
    /// reply actually needs to answer.
    struct Context: Equatable, Sendable {
        var isEnabled: Bool
        var isWithinWorkingHours: Bool
        var currentLocalTime: String
        var nextWorkingPeriod: String?
        var weeklySchedule: String?
    }

    /// - Parameter now: injectable so the behaviour is testable without waiting
    ///   for 18:30 to come round.
    func context(now: Date = Date(), calendar: Calendar = .current) -> Context {
        let time = TimeOfDay(
            minutes: calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        )

        guard isEnabled else {
            return Context(
                isEnabled: false,
                isWithinWorkingHours: true,
                currentLocalTime: time.formatted,
                nextWorkingPeriod: nil,
                weeklySchedule: nil
            )
        }

        let weekday = calendar.component(.weekday, from: now)
        let today = schedule(for: weekday)
        let isWithin = today.map { $0.isValid && time >= $0.start && time < $0.end } ?? false

        return Context(
            isEnabled: true,
            isWithinWorkingHours: isWithin,
            currentLocalTime: time.formatted,
            nextWorkingPeriod: isWithin ? nil : nextPeriodDescription(from: now, time: time, calendar: calendar),
            weeklySchedule: summary(calendar: calendar)
        )
    }

    /// A short English phrase such as "today 14:00", "tomorrow 10:00" or
    /// "Monday 10:00".
    ///
    /// Deliberately English and deliberately machine-ish: it is model context,
    /// not UI. The model renders it into the conversation's own language, which
    /// is what makes a Kazakh reply say "ертең 10:00" without this file needing
    /// to know how to decline a Kazakh weekday.
    private func nextPeriodDescription(from now: Date, time: TimeOfDay, calendar: Calendar) -> String? {
        let currentWeekday = calendar.component(.weekday, from: now)

        // Later today?
        if let today = schedule(for: currentWeekday), today.isValid, time < today.start {
            return "today \(today.start.formatted)"
        }

        // The next seven days, so a schedule with exactly one open day still
        // resolves rather than returning nil.
        for offset in 1...7 {
            let weekday = ((currentWeekday - 1 + offset) % 7) + 1
            guard let day = schedule(for: weekday), day.isValid else { continue }
            if offset == 1 { return "tomorrow \(day.start.formatted)" }
            let name = calendar.standaloneWeekdaySymbols[weekday - 1]
            return "\(name) \(day.start.formatted)"
        }
        return nil
    }

    /// Compact description of the whole week, grouping consecutive days that
    /// share the same hours: "Mon-Fri 10:00-16:00, Sat 11:00-14:00".
    private func summary(calendar: Calendar) -> String? {
        // Monday-first ordering reads correctly regardless of whether the
        // user's locale starts its week on Sunday.
        let ordered = [2, 3, 4, 5, 6, 7, 1].compactMap { schedule(for: $0) }.filter(\.isValid)
        guard !ordered.isEmpty else { return nil }

        let symbols = calendar.shortStandaloneWeekdaySymbols
        var groups: [String] = []
        var index = 0

        while index < ordered.count {
            let first = ordered[index]
            var last = index
            while last + 1 < ordered.count,
                  ordered[last + 1].start == first.start,
                  ordered[last + 1].end == first.end,
                  isAdjacent(ordered[last].weekday, ordered[last + 1].weekday) {
                last += 1
            }
            let range = last > index
                ? "\(symbols[first.weekday - 1])-\(symbols[ordered[last].weekday - 1])"
                : symbols[first.weekday - 1]
            groups.append("\(range) \(first.start.formatted)-\(first.end.formatted)")
            index = last + 1
        }
        return groups.joined(separator: ", ")
    }

    /// Adjacency in Monday-first order, so Saturday and Sunday group together
    /// and Sunday never groups onto Monday.
    private func isAdjacent(_ lhs: Int, _ rhs: Int) -> Bool {
        func position(_ weekday: Int) -> Int { weekday == 1 ? 6 : weekday - 2 }
        return position(rhs) == position(lhs) + 1
    }
}
