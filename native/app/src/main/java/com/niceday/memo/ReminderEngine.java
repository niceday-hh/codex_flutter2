package com.niceday.memo;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import org.json.*;
import java.util.*;

/** Native persistent alarm engine. Works without a running Flutter isolate. */
public final class ReminderEngine {
    public static final String BASE = "com.niceday.memo.BASE";
    public static final String RETRY = "com.niceday.memo.RETRY";
    public static final String ACK = "com.niceday.memo.ACK";
    private final Context context;
    private final SharedPreferences prefs;
    private final AlarmManager alarms;
    private final NotificationManager notifications;

    public ReminderEngine(Context context) {
        this.context = context.getApplicationContext();
        prefs = this.context.getSharedPreferences("memo", Context.MODE_PRIVATE);
        alarms = (AlarmManager) this.context.getSystemService(Context.ALARM_SERVICE);
        notifications = (NotificationManager) this.context.getSystemService(Context.NOTIFICATION_SERVICE);
    }
    private JSONArray read() throws JSONException {
        return new JSONArray(prefs.getString("reminders", "[]"));
    }
    private void write(JSONArray rows) {
        if (!prefs.edit().putString("reminders", rows.toString()).commit()) {
            throw new IllegalStateException("保存失败，请检查存储空间");
        }
    }
    private JSONObject find(JSONArray rows, int id) throws JSONException {
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            if (r.getInt("id") == id) return r;
        }
        return null;
    }
    public String state() throws JSONException {
        JSONObject result = new JSONObject();
        result.put("reminders", read());
        result.put("defaults", new JSONObject(prefs.getString("defaults", "{}")));
        JSONObject status = new JSONObject();
        status.put("notifications", notifications.areNotificationsEnabled());
        status.put("exact", Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms());
        PowerManager power = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        status.put("battery", power.isIgnoringBatteryOptimizations(context.getPackageName()));
        status.put("lastError", prefs.getString("lastError", ""));
        result.put("status", status);
        return result.toString();
    }
    public void defaults(String json) throws JSONException {
        new JSONObject(json);
        if (!prefs.edit().putString("defaults", json).commit()) throw new IllegalStateException("保存失败");
    }
    public void save(String json) throws JSONException {
        JSONObject r = new JSONObject(json);
        if (r.optString("text").trim().isEmpty()) throw new IllegalArgumentException("请输入提醒内容");
        if (r.optString("text").length() > 2000) throw new IllegalArgumentException("提醒内容不能超过2000字");
        if (r.optInt("intervalMinutes") < 1 || r.optInt("intervalMinutes") > 1440)
            throw new IllegalArgumentException("提醒间隔须为1至1440分钟");
        if (r.optInt("totalCount") < 1 || r.optInt("totalCount") > 20)
            throw new IllegalArgumentException("提醒总次数须为1至20次");
        if ("weekly".equals(r.optString("repeat")) && r.optJSONArray("days").length() == 0)
            throw new IllegalArgumentException("请选择重复星期");
        JSONArray rows = read();
        int id = r.optInt("id");
        if (id == 0) {
            id = prefs.getInt("nextId", 1);
            prefs.edit().putInt("nextId", id + 1).commit();
            r.put("id", id);
        }
        long now = System.currentTimeMillis();
        long next = next(r, now);
        if (r.optBoolean("enabled", true) && next == 0)
            throw new IllegalArgumentException("请选择未来的日期和时间");
        r.put("version", now);
        r.put("nextTrigger", r.optBoolean("enabled", true) ? next : 0);
        r.put("activeOccurrence", 0);
        r.put("attempts", 0);
        r.put("retryAt", 0);
        r.put("acknowledged", false);
        r.put("completed", false);
        JSONArray replacement = new JSONArray();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject old = rows.getJSONObject(i);
            if (old.getInt("id") != id) replacement.put(old);
        }
        replacement.put(r);
        // Persist the new generation before cancelling old alarms: stale delivery is rejected.
        write(replacement);
        cancel(id, BASE);
        cancel(id, RETRY);
        notifications.cancel(id);
        scheduleBase(r);
    }
    public void delete(int id) throws JSONException {
        JSONArray rows = read(), replacement = new JSONArray();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            if (r.getInt("id") != id) replacement.put(r);
        }
        write(replacement);
        cancel(id, BASE); cancel(id, RETRY); notifications.cancel(id);
    }
    public void acknowledge(int id, long token) throws JSONException {
        JSONArray rows = read();
        JSONObject r = find(rows, id);
        if (r == null || token == 0 || r.optLong("activeOccurrence") != token) return;
        r.put("acknowledged", true);
        r.put("retryAt", 0);
        r.put("lastAck", System.currentTimeMillis());
        if ("none".equals(r.optString("repeat"))) {
            r.put("enabled", false); r.put("completed", true);
        }
        write(rows);
        cancel(id, RETRY);
        notifications.cancel(id);
    }
    private long next(JSONObject r, long after) throws JSONException {
        Set<Integer> days = new HashSet<>();
        JSONArray array = r.optJSONArray("days");
        if (array != null) for (int i = 0; i < array.length(); i++) days.add(array.getInt(i));
        return Schedule.next(r.getInt("year"), r.getInt("month"), r.getInt("day"),
            r.getInt("hour"), r.getInt("minute"), r.optString("repeat", "none"), days,
            after, TimeZone.getDefault());
    }
    private PendingIntent intent(JSONObject r, String action, long token) throws JSONException {
        int id = r.getInt("id");
        Intent intent = new Intent(context, ReminderReceiver.class).setAction(action)
            .setData(Uri.parse("memo://" + action + "/" + id))
            .putExtra("id", id).putExtra("token", token).putExtra("version", r.optLong("version"));
        return PendingIntent.getBroadcast(context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
    private void schedule(JSONObject r, String action, long timestamp, long token) throws JSONException {
        if (timestamp <= 0) return;
        PendingIntent operation = intent(r, action, token);
        try {
            if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, operation);
            } else {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, operation);
            }
        } catch (SecurityException e) {
            // Permission may be revoked between checking and scheduling.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, operation);
            error("精确定时权限已被关闭，提醒可能延后");
        }
    }
    private void scheduleBase(JSONObject r) throws JSONException {
        schedule(r, BASE, r.optLong("nextTrigger"), r.optLong("nextTrigger"));
    }
    private void cancel(int id, String action) {
        Intent i = new Intent(context, ReminderReceiver.class).setAction(action)
            .setData(Uri.parse("memo://" + action + "/" + id));
        PendingIntent pi = PendingIntent.getBroadcast(context, id, i,
            PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE);
        if (pi != null) { alarms.cancel(pi); pi.cancel(); }
    }
    public void fire(Intent intent) throws JSONException {
        int id = intent.getIntExtra("id", 0);
        long token = intent.getLongExtra("token", 0);
        JSONArray rows = read();
        JSONObject r = find(rows, id);
        if (r == null || !r.optBoolean("enabled", true) ||
            r.optLong("version") != intent.getLongExtra("version", -1)) return;
        long now = System.currentTimeMillis();
        boolean isRetry = RETRY.equals(intent.getAction());
        if (isRetry) {
            if (r.optLong("activeOccurrence") != token || r.optLong("retryAt") == 0 ||
                !Schedule.mayRetry(r.optBoolean("acknowledged"), r.optInt("attempts"), r.optInt("totalCount"))) return;
            // Reject a duplicated or early broadcast without consuming an attempt.
            if (now + 1000 < r.optLong("retryAt")) return;
        } else {
            if (token == 0 || r.optLong("nextTrigger") != token || now + 1000 < token) return;
            cancel(id, RETRY);
            r.put("activeOccurrence", token);
            r.put("attempts", 0);
            r.put("acknowledged", false);
            r.put("nextTrigger", next(r, now));
        }
        r.put("attempts", r.optInt("attempts") + 1);
        r.put("lastFired", now);
        long retryAt = Schedule.mayRetry(false, r.optInt("attempts"), r.optInt("totalCount"))
            ? now + r.optInt("intervalMinutes") * 60000L : 0;
        r.put("retryAt", retryAt);
        write(rows);
        scheduleBase(r);
        schedule(r, RETRY, retryAt, token);
        notify(r, token);
    }
    public void restore(boolean wallClockChanged) throws JSONException {
        JSONArray rows = read();
        long now = System.currentTimeMillis();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            if (!r.optBoolean("enabled", true)) continue;
            if (wallClockChanged && r.optLong("nextTrigger") > 0) {
                // Fixed-date one-offs retain their original wall clock; past dates trigger once.
                long n = next(r, "none".equals(r.optString("repeat")) ? 0 : now);
                r.put("nextTrigger", n);
            }
        }
        write(rows);
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            if (!r.optBoolean("enabled", true)) continue;
            scheduleBase(r);
            if (r.optLong("activeOccurrence") > 0 && r.optLong("retryAt") > 0 &&
                Schedule.mayRetry(r.optBoolean("acknowledged"), r.optInt("attempts"), r.optInt("totalCount"))) {
                schedule(r, RETRY, Math.max(now + 1000, r.optLong("retryAt")), r.optLong("activeOccurrence"));
            }
        }
    }
    @SuppressWarnings("deprecation")
    private void notify(JSONObject r, long token) throws JSONException {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED) { error("通知权限未开启"); return; }
        boolean sound = r.optBoolean("sound", true);
        String vibration = r.optString("vibration", "three");
        Uri ringtone = r.optString("ringtone").isEmpty()
            ? RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            : Uri.parse(r.getString("ringtone"));
        String channelId = "memo_v1_" + Integer.toHexString((sound + ":" + vibration + ":" + ringtone).hashCode());
        NotificationChannel channel = new NotificationChannel(channelId, "备忘录提醒 · " + vibration,
            NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("到时提醒与未读再次提醒；滑动消除即可确认本次提醒");
        channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
        channel.enableVibration(!"off".equals(vibration));
        if (!"system".equals(vibration) && !"off".equals(vibration)) {
            long[] pattern = switch (vibration) {
                case "once" -> new long[]{0, 250};
                case "twice" -> new long[]{0, 250, 200, 250};
                case "strong" -> new long[]{0, 700, 250, 700};
                default -> new long[]{0, 200, 200, 200, 200, 200};
            };
            channel.setVibrationPattern(pattern);
        }
        channel.setSound(sound ? ringtone : null, new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
        notifications.createNotificationChannel(channel);
        int id = r.getInt("id");
        Intent open = new Intent(context, MainActivity.class)
            .setAction("com.niceday.memo.OPEN").setData(Uri.parse("memo://open/" + id))
            .putExtra("reminderId", id).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent content = PendingIntent.getActivity(context, id, open,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        PendingIntent dismiss = intent(r, ACK, token);
        KeyguardManager keyguard = (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
        boolean locked = keyguard.isKeyguardLocked();
        Notification publicVersion = new Notification.Builder(context, channelId)
            .setSmallIcon(com.niceday.memo.R.drawable.ic_notification)
            .setContentTitle("定时备忘录").setContentText("有一条待办提醒 · 解锁后查看")
            .setVisibility(Notification.VISIBILITY_PUBLIC).build();
        Notification.Builder builder = new Notification.Builder(context, channelId)
            .setSmallIcon(com.niceday.memo.R.drawable.ic_notification)
            .setColor(0xFF7252F6).setContentTitle("定时备忘录")
            // Also redact the actual payload when locked, even if system privacy settings are permissive.
            .setContentText(locked ? "有一条待办提醒 · 解锁后查看" : r.getString("text"))
            .setSubText("第" + r.optInt("attempts") + "/" + r.optInt("totalCount") + "次 · 划掉即确认")
            .setVisibility(Notification.VISIBILITY_PRIVATE).setPublicVersion(publicVersion)
            .setCategory(Notification.CATEGORY_REMINDER).setContentIntent(content)
            .setDeleteIntent(dismiss).setAutoCancel(false).setOnlyAlertOnce(false);
        if (Build.VERSION.SDK_INT >= 29) builder.setAllowSystemGeneratedContextualActions(false);
        if (!locked) builder.setStyle(new Notification.BigTextStyle().bigText(r.getString("text")));
        notifications.notify(id, builder.build());
        if (r.optBoolean("wakeScreen", true)) {
            try {
                PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
                PowerManager.WakeLock wake = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK | PowerManager.ACQUIRE_CAUSES_WAKEUP, "memo:reminder-screen");
                wake.acquire(5000);
            } catch (SecurityException e) { error("系统限制主动亮屏，请开启系统锁屏通知亮屏"); }
        }
    }
    public void error(String message) { prefs.edit().putString("lastError", message).apply(); }
}
