package kz.yerek.aireply

import kz.yerek.aireply.domain.model.DaySchedule
import kz.yerek.aireply.domain.model.TimeOfDay
import kz.yerek.aireply.domain.model.WorkingHours
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime

class WorkingHoursTest {

    /** 2026-09-15 is a Tuesday. */
    private val tuesdayNoon = LocalDateTime.of(2026, 9, 15, 12, 0)
    private val tuesdayEvening = LocalDateTime.of(2026, 9, 15, 19, 30)
    private val saturday = LocalDateTime.of(2026, 9, 19, 12, 0)

    @Test
    fun `disabled hours report as always available and send nothing`() {
        val context = WorkingHours.DEFAULT.context(tuesdayEvening)
        assertFalse(context.isEnabled)
        assertTrue(context.isWithinWorkingHours)
        assertNull(context.nextWorkingPeriod)
        assertNull(context.weeklySchedule)
    }

    @Test
    fun `inside hours on a weekday`() {
        val hours = WorkingHours.DEFAULT.copy(isEnabled = true)
        assertTrue(hours.context(tuesdayNoon).isWithinWorkingHours)
    }

    @Test
    fun `outside hours in the evening, with tomorrow as the next window`() {
        val hours = WorkingHours.DEFAULT.copy(isEnabled = true)
        val context = hours.context(tuesdayEvening)
        assertFalse(context.isWithinWorkingHours)
        assertEquals("tomorrow 10:00", context.nextWorkingPeriod)
    }

    @Test
    fun `before opening, the next window is today`() {
        val hours = WorkingHours.DEFAULT.copy(isEnabled = true)
        val context = hours.context(LocalDateTime.of(2026, 9, 15, 7, 0))
        assertFalse(context.isWithinWorkingHours)
        assertEquals("today 10:00", context.nextWorkingPeriod)
    }

    @Test
    fun `on a closed day, the next window names the weekday`() {
        val hours = WorkingHours.DEFAULT.copy(isEnabled = true)
        val context = hours.context(saturday)
        assertFalse(context.isWithinWorkingHours)
        assertEquals("Monday 10:00", context.nextWorkingPeriod)
    }

    @Test
    fun `consecutive days with the same hours are grouped`() {
        val hours = WorkingHours.DEFAULT.copy(isEnabled = true)
        assertEquals("Mon-Fri 10:00-16:00", hours.context(tuesdayNoon).weeklySchedule)
    }

    @Test
    fun `a differing weekend day gets its own group and sunday never joins monday`() {
        val hours = WorkingHours.DEFAULT
            .copy(isEnabled = true)
            .withDay(7) { it.copy(isEnabled = true, start = TimeOfDay.of(11, 0), end = TimeOfDay.of(14, 0)) }
        val summary = hours.context(tuesdayNoon).weeklySchedule
        assertEquals("Mon-Fri 10:00-16:00, Sat 11:00-14:00", summary)
    }

    @Test
    fun `a schedule with one open day still resolves a next window`() {
        val days = (1..7).map { weekday ->
            DaySchedule(
                weekday = weekday,
                isEnabled = weekday == 4,
                start = TimeOfDay.of(9, 0),
                end = TimeOfDay.of(10, 0)
            )
        }
        val hours = WorkingHours(isEnabled = true, days = days)
        // Wednesday is Calendar weekday 4; from Tuesday that is tomorrow.
        assertEquals("tomorrow 09:00", hours.context(tuesdayNoon).nextWorkingPeriod)
    }

    @Test
    fun `an inverted day is never treated as open`() {
        val hours = WorkingHours.DEFAULT
            .copy(isEnabled = true)
            .withDay(3) { it.copy(start = TimeOfDay.of(18, 0), end = TimeOfDay.of(9, 0)) }
        assertFalse(hours.schedule(3)!!.isValid)
        assertFalse(hours.context(tuesdayNoon).isWithinWorkingHours)
    }

    @Test
    fun `time of day is clamped and formatted as 24 hour`() {
        assertEquals("00:00", TimeOfDay(-5).formatted)
        assertEquals("23:59", TimeOfDay(99_999).formatted)
        assertEquals("09:05", TimeOfDay.of(9, 5).formatted)
    }

    @Test
    fun `calendar weekday mapping matches the iOS convention of sunday equals one`() {
        assertEquals(1, WorkingHours.calendarWeekday(java.time.DayOfWeek.SUNDAY))
        assertEquals(2, WorkingHours.calendarWeekday(java.time.DayOfWeek.MONDAY))
        assertEquals(7, WorkingHours.calendarWeekday(java.time.DayOfWeek.SATURDAY))
        assertEquals(java.time.DayOfWeek.SUNDAY, WorkingHours.dayOfWeek(1))
        assertEquals(java.time.DayOfWeek.MONDAY, WorkingHours.dayOfWeek(2))
    }
}
