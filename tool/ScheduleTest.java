import com.niceday.memo.Schedule;
import java.time.*;
import java.util.*;

public class ScheduleTest {
    static long time(String iso, String zone) { return LocalDateTime.parse(iso).atZone(ZoneId.of(zone)).toInstant().toEpochMilli(); }
    static void equal(long a, long b, String label) { if (a != b) throw new AssertionError(label + ": " + a + " != " + b); }
    public static void main(String[] args) {
        String zone = "Asia/Shanghai";
        TimeZone tz = TimeZone.getTimeZone(zone);
        long now = time("2026-10-14T08:00:00", zone);
        equal(Schedule.next(2026, 10, 14, 9, 0, "none", Set.of(), now, tz), time("2026-10-14T09:00:00", zone), "one-off");
        equal(Schedule.next(2026, 10, 14, 7, 0, "none", Set.of(), now, tz), 0, "past one-off");
        equal(Schedule.next(2026, 10, 14, 9, 0, "weekly", Set.of(3), time("2026-10-14T09:00:00", zone), tz), time("2026-10-21T09:00:00", zone), "weekly");
        equal(Schedule.next(2026, 10, 14, 9, 0, "daily", Set.of(), time("2026-10-14T09:00:00", zone), tz), time("2026-10-15T09:00:00", zone), "daily");
        equal(Schedule.next(2026, 10, 14, 9, 0, "weekly", Set.of(1,2,3,4,5), time("2026-10-16T12:00:00", zone), tz), time("2026-10-19T09:00:00", zone), "skip weekend");
        equal(Schedule.next(2026, 12, 31, 9, 0, "daily", Set.of(), time("2026-12-31T12:00:00", zone), tz), time("2027-01-01T09:00:00", zone), "year rollover");
        String dst = "America/New_York";
        equal(Schedule.next(2026, 3, 7, 9, 0, "daily", Set.of(), time("2026-03-07T12:00:00", dst), TimeZone.getTimeZone(dst)), time("2026-03-08T09:00:00", dst), "DST wall clock");
        if (!Schedule.mayRetry(false, 1, 3)) throw new AssertionError("first reminder permits retry");
        if (Schedule.mayRetry(false, 3, 3)) throw new AssertionError("total count includes first");
        if (Schedule.mayRetry(true, 1, 3)) throw new AssertionError("ack cancels retries");
        if (Schedule.mayRetry(false, 1, 1)) throw new AssertionError("one total means no retries");
        System.out.println("11 scheduling/retry checks passed");
    }
}
