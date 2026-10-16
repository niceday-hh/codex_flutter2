package com.niceday.memo;

import java.util.Calendar;
import java.util.Set;
import java.util.TimeZone;

/** Pure wall-clock scheduling, independent of Android and testable on the JVM. */
public final class Schedule {
    private Schedule() {}
    public static long next(int year, int month, int day, int hour, int minute,
                            String repeat, Set<Integer> days, long after, TimeZone zone) {
        return next(year, month, day, hour, minute, 0, 0, repeat, days, after, zone);
    }
    public static long next(int year, int month, int day, int hour, int minute, int second, int millisecond,
                            String repeat, Set<Integer> days, long after, TimeZone zone) {
        Calendar anchor = Calendar.getInstance(zone);
        anchor.clear();
        anchor.set(year, month - 1, day, hour, minute, second);
        anchor.set(Calendar.MILLISECOND, millisecond);
        long base = anchor.getTimeInMillis();
        if ("none".equals(repeat)) return base > after ? base : 0;
        Calendar candidate = Calendar.getInstance(zone);
        candidate.setTimeInMillis(Math.max(base, after));
        candidate.set(Calendar.HOUR_OF_DAY, hour);
        candidate.set(Calendar.MINUTE, minute);
        candidate.set(Calendar.SECOND, second);
        candidate.set(Calendar.MILLISECOND, millisecond);
        for (int i = 0; i < 9; i++) {
            long stamp = candidate.getTimeInMillis();
            int isoDay = (candidate.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1;
            if (stamp >= base && stamp > after &&
                ("daily".equals(repeat) || days.contains(isoDay))) return stamp;
            candidate.add(Calendar.DAY_OF_MONTH, 1);
        }
        return 0;
    }
    public static boolean mayRetry(boolean acknowledged, int attempts, int totalCount) {
        return !acknowledged && attempts < totalCount;
    }
}
