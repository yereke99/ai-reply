import XCTest
@testable import AIReply

/// Working-hours derivation. Time behaviour is the easiest thing in this app to
/// get subtly wrong and the hardest to notice, so `context(now:)` takes an
/// injectable clock and these tests pin it down.
final class WorkingHoursTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // Fixed so the assertions do not depend on where the machine is.
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var monToFri10to16: WorkingHours {
        WorkingHours(
            isEnabled: true,
            days: (1...7).map { weekday in
                DaySchedule(
                    weekday: weekday,
                    isEnabled: weekday >= 2 && weekday <= 6,
                    start: TimeOfDay(hour: 10, minute: 0),
                    end: TimeOfDay(hour: 16, minute: 0)
                )
            }
        )
    }

    func testInsideWorkingHours() {
        // Wednesday 2026-09-09, 14:00.
        let context = monToFri10to16.context(now: date(2026, 9, 9, 14, 0), calendar: calendar)
        XCTAssertTrue(context.isWithinWorkingHours)
        XCTAssertEqual(context.currentLocalTime, "14:00")
        // Nothing to announce while open.
        XCTAssertNil(context.nextWorkingPeriod)
    }

    func testAfterHoursPointsAtTomorrow() {
        // Wednesday 18:30, the brief's own example.
        let context = monToFri10to16.context(now: date(2026, 9, 9, 18, 30), calendar: calendar)
        XCTAssertFalse(context.isWithinWorkingHours)
        XCTAssertEqual(context.currentLocalTime, "18:30")
        XCTAssertEqual(context.nextWorkingPeriod, "tomorrow 10:00")
    }

    func testBeforeOpeningPointsAtToday() {
        let context = monToFri10to16.context(now: date(2026, 9, 9, 8, 15), calendar: calendar)
        XCTAssertFalse(context.isWithinWorkingHours)
        XCTAssertEqual(context.nextWorkingPeriod, "today 10:00")
    }

    func testWeekendSkipsToMonday() {
        // Saturday 2026-09-12.
        let context = monToFri10to16.context(now: date(2026, 9, 12, 12, 0), calendar: calendar)
        XCTAssertFalse(context.isWithinWorkingHours)
        // Two days out, so it names the day rather than saying "tomorrow".
        XCTAssertEqual(context.nextWorkingPeriod?.hasSuffix("10:00"), true)
        XCTAssertEqual(context.nextWorkingPeriod?.contains("tomorrow"), false)
    }

    func testSundayEveningSaysTomorrow() {
        // Sunday 2026-09-13, 20:00 -> Monday.
        let context = monToFri10to16.context(now: date(2026, 9, 13, 20, 0), calendar: calendar)
        XCTAssertEqual(context.nextWorkingPeriod, "tomorrow 10:00")
    }

    func testDisabledHoursSendNoTimeContext() {
        var hours = monToFri10to16
        hours.isEnabled = false
        let context = hours.context(now: date(2026, 9, 9, 18, 30), calendar: calendar)
        XCTAssertFalse(context.isEnabled)
        XCTAssertNil(context.nextWorkingPeriod)
        XCTAssertNil(context.weeklySchedule)
        // Never "closed" when the user never said they had hours.
        XCTAssertTrue(context.isWithinWorkingHours)
    }

    func testWeeklySummaryGroupsConsecutiveDays() {
        let summary = monToFri10to16.context(now: date(2026, 9, 9, 14, 0), calendar: calendar).weeklySchedule
        XCTAssertNotNil(summary)
        // One grouped range, not five separate days.
        XCTAssertEqual(summary?.contains(","), false)
        XCTAssertEqual(summary?.contains("10:00-16:00"), true)
    }

    func testEndBeforeStartIsNeverInside() {
        let broken = WorkingHours(
            isEnabled: true,
            days: [DaySchedule(weekday: 4, isEnabled: true,
                               start: TimeOfDay(hour: 16, minute: 0),
                               end: TimeOfDay(hour: 10, minute: 0))]
        )
        let context = broken.context(now: date(2026, 9, 9, 12, 0), calendar: calendar)
        XCTAssertFalse(context.isWithinWorkingHours)
    }

    func testTimeOfDayClampsOutOfRangeValues() {
        XCTAssertEqual(TimeOfDay(minutes: -30).minutes, 0)
        XCTAssertEqual(TimeOfDay(minutes: 99_999).formatted, "23:59")
        XCTAssertEqual(TimeOfDay(hour: 9, minute: 5).formatted, "09:05")
    }
}
