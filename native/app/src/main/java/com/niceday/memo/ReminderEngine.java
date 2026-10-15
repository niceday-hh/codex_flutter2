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
    private final SharedPreferences runtime;
    private final boolean unlocked;
    private final AlarmManager alarms;
    private final NotificationManager notifications;
    private final NotificationStyles styles;

    public ReminderEngine(Context context) {
        this.context = context.getApplicationContext();
        unlocked = this.context.getSystemService(UserManager.class).isUserUnlocked();
        runtime = this.context.createDeviceProtectedStorageContext().getSharedPreferences("memo-runtime", Context.MODE_PRIVATE);
        prefs = unlocked ? this.context.getSharedPreferences("memo", Context.MODE_PRIVATE) : runtime;
        alarms = (AlarmManager) this.context.getSystemService(Context.ALARM_SERVICE);
        notifications = (NotificationManager) this.context.getSystemService(Context.NOTIFICATION_SERVICE);
        styles = new NotificationStyles(this.context, notifications, runtime);
    }
    private static final String[] RUNTIME_FIELDS = {"nextTrigger", "activeOccurrence", "attempts", "retryAt",
        "acknowledged", "completed", "enabled", "lastAck", "lastFired", "metaRevision"};
    private JSONArray read() throws JSONException {
        JSONArray rows = new JSONArray(prefs.getString("reminders", "[]"));
        if (!unlocked) return rows;
        JSONArray mirror = new JSONArray(runtime.getString("reminders", "[]"));
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            JSONObject m = find(mirror, r.getInt("id"));
            if (m != null && m.optLong("version") == r.optLong("version") && m.optLong("metaRevision") > r.optLong("metaRevision")) {
                for (String name : RUNTIME_FIELDS) if (m.has(name)) r.put(name, m.get(name));
            }
        }
        return rows;
    }
    private void write(JSONArray rows) throws JSONException {
        long revision = runtime.getLong("revision", 0) + 1;
        JSONArray mirror = new JSONArray();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            r.put("metaRevision", revision);
            JSONObject m = new JSONObject(r.toString());
            m.remove("text"); m.put("ringtone", "");
            mirror.put(m);
        }
        if (unlocked && !prefs.edit().putString("reminders", rows.toString()).commit())
            throw new IllegalStateException("保存失败，请检查存储空间");
        if (!runtime.edit().putString("reminders", mirror.toString()).putLong("revision", revision).commit())
            throw new IllegalStateException("无法保存开机提醒排程");
    }
    private void trace(String type, int id, long at, String detail) {
        try {
            JSONArray old = new JSONArray(runtime.getString("trace", "[]"));
            JSONArray log = new JSONArray();
            for (int i = Math.max(0, old.length() - 39); i < old.length(); i++) log.put(old.get(i));
            log.put(new JSONObject().put("type", type).put("id", id).put("at", System.currentTimeMillis())
                .put("planned", at).put("detail", detail).put("pid", android.os.Process.myPid()));
            runtime.edit().putString("trace", log.toString()).commit();
        } catch (JSONException ignored) {}
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
        JSONArray rows = read();
        JSONObject defaults = new JSONObject(prefs.getString("defaults", "{}"));
        BackupCodec.validateStyle(defaults);
        JSONArray groups = styles.groups(rows, new JSONObject(defaults.toString()), unlocked);
        result.put("reminders", rows);
        result.put("defaults", defaults);
        JSONObject status = new JSONObject();
        status.put("notifications", notifications.areNotificationsEnabled());
        status.put("exact", Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms());
        PowerManager power = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        status.put("battery", power.isIgnoringBatteryOptimizations(context.getPackageName()));
        status.put("lastError", runtime.getString("lastError", ""));
        status.put("trace", new JSONArray(runtime.getString("trace", "[]")));
        status.put("lastReceived", runtime.getLong("lastReceived", 0));
        status.put("lastRestored", runtime.getLong("lastRestored", 0));
        status.put("package", context.getPackageName());
        status.put("version", "0.3.0");
        status.put("notificationStyles", groups);
        status.put("hiddenChannelCount", styles.hiddenCount(groups));
        result.put("status", status);
        return result.toString();
    }
    public void defaults(String json) throws JSONException {
        JSONObject values = new JSONObject(json);
        BackupCodec.validateStyle(values);
        values.remove("notificationChannelId"); values.remove("notificationStyle");
        ensureChannel(new JSONObject(values.toString()));
        if (!prefs.edit().putString("defaults", values.toString()).commit()) throw new IllegalStateException("保存失败");
    }
    public String channelForStyle(String json) throws JSONException {
        JSONObject values = new JSONObject(json);
        BackupCodec.validateStyle(values);
        return ensureChannel(values);
    }
    public void save(String json) throws JSONException {
        JSONObject r = new JSONObject(json);
        r.remove("notificationChannelId"); r.remove("notificationStyle");
        BackupCodec.validateReminder(r);
        if (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms())
            throw new IllegalArgumentException("请先开启闹钟与提醒权限，白名单和电池优化不能替代这项权限");
        if (!notifications.areNotificationsEnabled()) throw new IllegalArgumentException("请先允许应用通知");
        // Saving an edited task is an explicit new activation, including a completed task.
        r.put("enabled", true);
        JSONArray rows = read();
        int id = r.optInt("id");
        if (id == 0) {
            id = prefs.getInt("nextId", 1);
            for (int i = 0; i < rows.length(); i++) id = Math.max(id, rows.getJSONObject(i).getInt("id") + 1);
            prefs.edit().putInt("nextId", id + 1).commit();
            r.put("id", id);
        }
        long now = System.currentTimeMillis();
        long next = next(r, now);
        if (r.optBoolean("enabled", true) && next == 0)
            throw new IllegalArgumentException("请选择未来的日期和时间");
        r.put("version", Math.max(now, prefs.getLong("generation", 0) + 1));
        prefs.edit().putLong("generation", r.getLong("version")).commit();
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
        ensureChannel(r);
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
        // User-visible alarms and dismissal must not wait behind slow background broadcasts.
        Intent intent = new Intent(context, ReminderReceiver.class).setAction(action)
            .setData(Uri.parse("memo://" + action + "/" + id))
            .addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            .putExtra("id", id).putExtra("token", token).putExtra("version", r.optLong("version"));
        // Recreate the token so an upgrade replaces older intents without foreground priority.
        return PendingIntent.getBroadcast(context, id, intent,
            PendingIntent.FLAG_CANCEL_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
    private PendingIntent showIntent(int id) {
        Intent show = new Intent(context, MainActivity.class).setAction("com.niceday.memo.OPEN")
            .setData(Uri.parse("memo://show/" + id)).putExtra("reminderId", id)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(context, id, show, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
    private void schedule(JSONObject r, String action, long timestamp, long token) throws JSONException {
        if (timestamp <= 0) return;
        PendingIntent operation = intent(r, action, token);
        try {
            if (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms())
                throw new SecurityException("闹钟与提醒权限未开启");
            alarms.setAlarmClock(new AlarmManager.AlarmClockInfo(timestamp, showIntent(r.getInt("id"))), operation);
            trace("scheduled", r.getInt("id"), timestamp, RETRY.equals(action) ? "未读再次提醒" : "系统闹钟排程");
        } catch (SecurityException e) {
            error("闹钟与提醒权限未开启，提醒未注册。请到设置修复");
            trace("schedule_failed", r.getInt("id"), timestamp, "缺少精确定时权限");
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
        runtime.edit().putLong("lastReceived", now).commit();
        trace("received", id, token, "原生广播触发");
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
        ensureChannel(r);
        write(rows);
        scheduleBase(r);
        schedule(r, RETRY, retryAt, token);
        notify(r, token);
    }
    public void restore(boolean wallClockChanged) throws JSONException { restore(wallClockChanged, "恢复排程"); }
    public void restore(boolean wallClockChanged, String reason) throws JSONException {
        JSONArray rows = read();
        if (unlocked && prefs.getInt("schema", 1) < 2) {
            for (int i = 0; i < rows.length(); i++) {
                JSONObject r = rows.getJSONObject(i);
                if (!r.optBoolean("enabled", true) && !r.optBoolean("completed") && r.optLong("activeOccurrence") == 0 && r.optLong("nextTrigger") == 0) {
                    long future = next(r, System.currentTimeMillis());
                    r.put("enabled", future > 0).put("completed", future == 0).put("nextTrigger", future);
                }
            }
            prefs.edit().putInt("schema", 2).commit();
        }
        runtime.edit().putLong("lastRestored", System.currentTimeMillis()).commit();
        trace("restored", 0, 0, reason);
        long now = System.currentTimeMillis();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            if (!r.optBoolean("enabled", true)) continue;
            if (wallClockChanged && r.optLong("nextTrigger") > 0) {
                // Fixed-date one-offs retain their original wall clock; past dates trigger once.
                long n = next(r, "none".equals(r.optString("repeat")) ? 0 : now);
                r.put("nextTrigger", n);
            }
            ensureChannel(r);
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
    private String ensureChannel(JSONObject r) throws JSONException {
        return styles.ensure(r, unlocked);
    }
    @SuppressWarnings("deprecation")
    private void notify(JSONObject r, long token) throws JSONException {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            error("通知权限未开启，系统闹钟已触发但无法显示通知"); return;
        }
        String channelId = ensureChannel(r);
        int id = r.getInt("id");
        Intent open = new Intent(context, MainActivity.class)
            .setAction("com.niceday.memo.OPEN").setData(Uri.parse("memo://open/" + id))
            .putExtra("reminderId", id).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent content = PendingIntent.getActivity(context, id, open,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        PendingIntent dismiss = intent(r, ACK, token);
        KeyguardManager keyguard = (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
        boolean locked = !unlocked || keyguard.isKeyguardLocked();
        Notification publicVersion = new Notification.Builder(context, channelId)
            .setSmallIcon(com.niceday.memo.R.drawable.ic_notification)
            .setContentTitle("定时备忘录").setContentText("有一条待办提醒 · 解锁后查看")
            .setVisibility(Notification.VISIBILITY_PUBLIC).build();
        Notification.Builder builder = new Notification.Builder(context, channelId)
            .setSmallIcon(com.niceday.memo.R.drawable.ic_notification)
            .setColor(0xFF7252F6).setContentTitle("定时备忘录")
            // Also redact the actual payload when locked, even if system privacy settings are permissive.
            .setContentText(locked ? "有一条待办提醒 · 解锁后查看" : r.optString("text", "有一条待办提醒"))
            .setSubText("第" + r.optInt("attempts") + "/" + r.optInt("totalCount") + "次 · 划掉即确认")
            .setVisibility(NotificationStyles.visibility(r)).setPublicVersion(publicVersion)
            .setCategory(Notification.CATEGORY_ALARM).setContentIntent(content)
            .setDeleteIntent(dismiss).setAutoCancel(false).setOnlyAlertOnce(false);
        if (Build.VERSION.SDK_INT >= 29) builder.setAllowSystemGeneratedContextualActions(false);
        if (!locked) builder.setStyle(new Notification.BigTextStyle().bigText(r.optString("text", "有一条待办提醒")));
        notifications.notify(id, builder.build());
        NotificationChannel actual = notifications.getNotificationChannel(channelId);
        trace("notified", id, token, "importance=" + actual.getImportance() + ";redacted=" + locked);
        if (actual.getImportance() == NotificationManager.IMPORTANCE_NONE) error("此通知样式已被系统关闭，请打开对应的系统通知设置");
        else if (NotificationStyles.importance(r) == NotificationManager.IMPORTANCE_HIGH && actual.getImportance() < NotificationManager.IMPORTANCE_HIGH)
            error("系统通道未允许横幅，请打开这条提醒的系统通知设置");
        if (r.optBoolean("wakeScreen", true)) {
            try {
                PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
                PowerManager.WakeLock wake = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK | PowerManager.ACQUIRE_CAUSES_WAKEUP, "memo:reminder-screen");
                wake.acquire(5000);
            } catch (SecurityException e) { error("系统限制主动亮屏，请开启系统锁屏通知亮屏"); }
        }
    }
    public void error(String message) { runtime.edit().putString("lastError", message).commit(); }
    public String exportBackup() throws JSONException {
        if (!unlocked) throw new IllegalStateException("请先解锁手机");
        JSONArray portable = new JSONArray(), rows = read();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = new JSONObject(rows.getJSONObject(i).toString());
            r.remove("notificationChannelId"); r.remove("notificationStyle"); portable.put(r);
        }
        return new JSONObject().put("format", "timed-memo").put("version", 1)
            .put("exportedAt", System.currentTimeMillis()).put("reminders", portable)
            .put("defaults", new JSONObject(prefs.getString("defaults", "{}"))).toString(2);
    }
    public int importBackup(String source) throws JSONException {
        if (!unlocked) throw new IllegalStateException("请先解锁手机");
        JSONArray imported = BackupCodec.decode(source);
        JSONArray rows = read();
        int id = prefs.getInt("nextId", 1);
        for (int i = 0; i < rows.length(); i++) id = Math.max(id, rows.getJSONObject(i).getInt("id") + 1);
        long generation = Math.max(System.currentTimeMillis(), prefs.getLong("generation", 0) + 1);
        for (int i = 0; i < imported.length(); i++) {
            JSONObject r = imported.getJSONObject(i);
            long n = next(r, System.currentTimeMillis());
            boolean enabled = r.optBoolean("enabled", true) && n > 0 && !r.optBoolean("completed");
            r.put("id", id++).put("version", generation++).put("enabled", enabled)
                .put("nextTrigger", enabled ? n : 0).put("activeOccurrence", 0).put("attempts", 0)
                .put("retryAt", 0).put("acknowledged", false)
                .put("completed", r.optBoolean("completed") || ("none".equals(r.optString("repeat")) && n == 0))
                .put("ringtone", "");
            r.remove("notificationChannelId"); r.remove("notificationStyle");
            ensureChannel(r);
            rows.put(r);
        }
        // Validate the whole file before a single atomic data write; merge never overwrites local rows.
        write(rows);
        prefs.edit().putInt("nextId", id).putLong("generation", generation).putInt("schema", 2).commit();
        for (int i = rows.length() - imported.length(); i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i); ensureChannel(r); scheduleBase(r);
        }
        return imported.length();
    }
    public int createTest(int seconds) throws JSONException {
        seconds = Math.max(15, Math.min(300, seconds));
        JSONObject defaults = new JSONObject(prefs.getString("defaults", "{}"));
        BackupCodec.validateStyle(defaults);
        Calendar calendar = Calendar.getInstance(); calendar.add(Calendar.MINUTE, 1);
        JSONObject config = new JSONObject().put("id", 0).put("text", "后台提醒自检")
            .put("year", calendar.get(Calendar.YEAR)).put("month", calendar.get(Calendar.MONTH) + 1)
            .put("day", calendar.get(Calendar.DAY_OF_MONTH)).put("hour", calendar.get(Calendar.HOUR_OF_DAY))
            .put("minute", calendar.get(Calendar.MINUTE)).put("repeat", "none").put("days", new JSONArray())
            .put("enabled", true).put("sound", defaults.getBoolean("sound")).put("vibration", defaults.getString("vibration"))
            .put("wakeScreen", defaults.getBoolean("wakeScreen")).put("ringtone", defaults.getString("ringtone"))
            .put("presentation", defaults.getString("presentation")).put("lockscreen", defaults.getString("lockscreen"))
            .put("intervalMinutes", 5).put("totalCount", 1);
        save(config.toString());
        int id = prefs.getInt("nextId", 1) - 1;
        JSONArray rows = read(); JSONObject r = find(rows, id);
        long stamp = System.currentTimeMillis() + seconds * 1000L;
        Calendar actual = Calendar.getInstance(); actual.setTimeInMillis(stamp);
        r.put("year", actual.get(Calendar.YEAR)).put("month", actual.get(Calendar.MONTH) + 1)
            .put("day", actual.get(Calendar.DAY_OF_MONTH)).put("hour", actual.get(Calendar.HOUR_OF_DAY))
            .put("minute", actual.get(Calendar.MINUTE)).put("nextTrigger", stamp);
        write(rows); cancel(id, BASE); scheduleBase(r); return id;
    }
}
