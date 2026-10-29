package com.niceday.memo;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.drawable.Icon;
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
    public static final String ARCHIVE = "com.niceday.memo.ARCHIVE";
    public static final String DELETE = "com.niceday.memo.DELETE";
    public static final String SNOOZE = "com.niceday.memo.SNOOZE";
    public static final String MUTE = "com.niceday.memo.MUTE";
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
        if (unlocked) {
            migrateSpeechModel();
            try { SpeechSettings.migrateSeeds(this.context); } catch (JSONException e) { error("语音版本初始化失败"); }
        }
    }
    private void migrateSpeechModel() {
        if ("voine-vits-mnn-v1".equals(prefs.getString("speechModel", ""))) return;
        try {
            JSONArray rows = new JSONArray(prefs.getString("reminders", "[]"));
            for (int i=0;i<rows.length();i++) {
                JSONObject r=rows.getJSONObject(i);
                if (!r.optString("speechVoice").isEmpty()) r.put("speechVoice", SpeechSettings.VOICE);
                r.put("speechModel", "voine-vits-mnn-v1");
            }
            JSONObject defaults=new JSONObject(prefs.getString("defaults","{}"));
            defaults.put("speechVoice",SpeechSettings.VOICE).put("speechModel","voine-vits-mnn-v1");
            prefs.edit().putString("reminders",rows.toString()).putString("defaults",defaults.toString())
                .putString("speechModel","voine-vits-mnn-v1").commit();
            TtsAssets.clearLegacy(context); SpeechCache.prune(context);
        } catch(JSONException e) { error("音色迁移未完成，请导出备份后重试"); }
    }
    private static final String[] RUNTIME_FIELDS = {"nextTrigger", "activeOccurrence", "attempts", "retryAt",
        "acknowledged", "completed", "enabled", "lastAck", "lastFired", "metaRevision", "muted"};
    private JSONArray read() throws JSONException {
        JSONArray rows = new JSONArray(prefs.getString("reminders", "[]"));
        if (!unlocked) return rows;
        JSONArray mirror = new JSONArray(runtime.getString("reminders", "[]"));
        Map<Integer,JSONObject> mirrors = new HashMap<>();
        for (int i=0;i<mirror.length();i++) mirrors.put(mirror.getJSONObject(i).getInt("id"),mirror.getJSONObject(i));
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            JSONObject m = mirrors.get(r.getInt("id"));
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
        // The widget is a projection of this file; refresh it wherever the data
        // changes instead of running its own timer.
        MemoWidgetProvider.refresh(context);
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
    void event(String type, int id, long at, String detail) { trace(type, id, at, detail); }
    public boolean popupEnabled() { return runtime.getBoolean("popupEnabled", false); }
    public void popupMode(boolean enabled) {
        if (!runtime.edit().putBoolean("popupEnabled", enabled).commit()) throw new IllegalStateException("保存失败");
        if (!enabled) context.stopService(new Intent(context, ReminderPopupService.class));
    }
    void popupError(String value) { runtime.edit().putString("popupError", value).commit(); }
    JSONObject popupPayload(int id, long token) throws JSONException {
        if (!unlocked) return null;
        JSONObject row = find(read(), id);
        if (row == null || token <= 0 || row.optLong("activeOccurrence") != token || row.optBoolean("acknowledged") || !row.has("text")) return null;
        return row;
    }
    public boolean reliableMode() { return runtime.getBoolean("reliableMode", true); }
    public JSONObject pendingSummary() throws JSONException {
        JSONArray rows = read(); int count = 0; long earliest = 0;
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            if (!r.optBoolean("enabled", true)) continue;
            long base = r.optLong("nextTrigger"), retry = !r.optBoolean("acknowledged") ? r.optLong("retryAt") : 0;
            if (base > 0 || retry > 0) {
                count++; long at = base > 0 && retry > 0 ? Math.min(base, retry) : Math.max(base, retry);
                if (earliest == 0 || at < earliest) earliest = at;
            }
        }
        return new JSONObject().put("count", count).put("earliest", earliest);
    }
    public void reliableMode(boolean enabled) throws JSONException {
        if (enabled && (!notifications.areNotificationsEnabled() || (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms())))
            throw new IllegalArgumentException("请先开启通知及闹钟与提醒权限");
        if (!runtime.edit().putBoolean("reliableMode", enabled).commit()) throw new IllegalStateException("保存失败");
        trace("reliable_mode", 0, 0, enabled ? "开启" : "关闭"); syncGuardian();
    }
    void guardianError(String message) { runtime.edit().putString("guardianError", message).commit(); }
    private void syncGuardian() throws JSONException {
        Intent service = new Intent(context, ReminderGuardianService.class).setAction("com.niceday.memo.GUARDIAN_UPDATE");
        if (!reliableMode() || pendingSummary().getInt("count") == 0) { context.stopService(service); return; }
        if (!notifications.areNotificationsEnabled() || (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms())) {
            context.stopService(service); guardianError("可靠提醒需开启通知及精确定时权限"); return;
        }
        try { context.startForegroundService(service); }
        catch (RuntimeException e) { guardianError("系统未允许启动可靠提醒：" + e.getClass().getSimpleName()); }
    }
    public void captureSnapshot(String name) {
        try { runtime.edit().putString(name, ReminderDiagnostics.snapshot(context, read()).toString()).commit(); }
        catch (Exception e) { runtime.edit().putString(name, "{\"error\":\"snapshot_unavailable\"}").commit(); }
    }
    public String exportDiagnostics() throws JSONException {
        JSONObject current = ReminderDiagnostics.snapshot(context, read());
        JSONObject state = new JSONObject(state()).getJSONObject("status");
        state.remove("notificationStyles");
        return new JSONObject().put("format", "timed-memo-diagnostics").put("version", 1)
            .put("current", current).put("status", state)
            .put("launchBeforeRestore", new JSONObject(runtime.getString("launchSnapshot", "{}")))
            .put("serviceBeforeRestore", new JSONObject(runtime.getString("serviceLaunchSnapshot", "{}"))).toString(2);
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
        JSONObject speechDefaults = SpeechSettings.defaults(context);
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.getJSONObject(i);
            row.put("speechState", row.optBoolean("archived") || row.optBoolean("completed") ? "off" : SpeechCache.state(context, row, speechDefaults));
        }
        result.put("reminders", rows);
        result.put("defaults", defaults);
        result.put("voiceGroups", unlocked ? VoiceGroups.read(context) : new JSONArray());
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
        try { status.put("version", context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName); }
        catch (android.content.pm.PackageManager.NameNotFoundException ignored) { status.put("version", ""); }
        status.put("testAutoDelete",prefs.getBoolean("testAutoDelete",true));
        status.put("cleanupPrompts", prefs.getBoolean("cleanupPrompts",true));
        status.put("speech", SpeechCache.status(context));
        status.put("popupEnabled", popupEnabled());
        status.put("popupPermission", Settings.canDrawOverlays(context));
        status.put("popupError", runtime.getString("popupError", ""));
        status.put("reliableMode", reliableMode());
        status.put("guardianRunning", ReminderGuardianService.running(context));
        status.put("guardianError", runtime.getString("guardianError", ""));
        status.put("pending", pendingSummary());
        status.put("processExits", ReminderDiagnostics.exits(context));
        status.put("notificationStyles", groups);
        status.put("hiddenChannelCount", styles.hiddenCount(groups));
        result.put("status", status);
        return result.toString();
    }
    public void defaults(String json) throws JSONException {
        JSONObject values = new JSONObject(json);
        BackupCodec.validateStyle(values);
        SpeechSettings.validate(values, true);
        VoiceInputSettings.validate(values);
        values.remove("notificationChannelId"); values.remove("notificationStyle");
        ensureChannel(new JSONObject(values.toString()));
        JSONObject previous = SpeechSettings.defaults(context);
        JSONArray rows = new JSONArray(prefs.getString("reminders", "[]"));
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.getJSONObject(i);
            if (!SpeechSettings.profile(row, previous).equals(SpeechSettings.profile(row, values))) row.put("speechSeed", SpeechSettings.newSeed());
        }
        if (!prefs.edit().putString("defaults", values.toString()).putString("reminders", rows.toString()).commit()) throw new IllegalStateException("保存失败");
    }
    public String channelForStyle(String json) throws JSONException {
        JSONObject values = new JSONObject(json);
        BackupCodec.validateStyle(values);
        return ensureChannel(values);
    }
    public void save(String json) throws JSONException {
        JSONObject r = new JSONObject(json);
        r.remove("notificationChannelId"); r.remove("notificationStyle"); r.remove("historyScheduledAt");
        BackupCodec.validateReminder(r);
        VoiceCatalog.resolve(context,r);
        if (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms())
            throw new IllegalArgumentException("请先开启闹钟与提醒权限，白名单和电池优化不能替代这项权限");
        if (!notifications.areNotificationsEnabled()) throw new IllegalArgumentException("请先允许应用通知");
        // Saving an edited task is an explicit new activation, including a completed task.
        r.put("enabled", true);
        JSONArray rows = read();
        int id = r.optInt("id");
        JSONObject existing = find(rows, id), speechDefaults = SpeechSettings.defaults(context);
        if (existing != null && SpeechSettings.profile(existing, speechDefaults).equals(SpeechSettings.profile(r, speechDefaults)))
            r.put("speechSeed", SpeechSettings.seed(existing));
        else r.put("speechSeed", SpeechSettings.newSeed());
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
        r.put("archived", false).put("archivedAt",0).remove("cleanupPending");
        JSONArray replacement = new JSONArray();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject old = rows.getJSONObject(i);
            if (old.getInt("id") != id) replacement.put(old);
        }
        replacement.put(r);
        // Persist the new generation before cancelling old alarms: stale delivery is rejected.
        ensureChannel(r);
        write(replacement);
        SpeechPlaybackService.cancel(id);
        cancel(id, BASE);
        cancel(id, RETRY);
        notifications.cancel(id);
        notifications.cancel(-id);
        scheduleBase(r);
        syncGuardian();
    }
    public void delete(int id) throws JSONException {
        JSONArray rows = read(), replacement = new JSONArray();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            if (r.getInt("id") != id) replacement.put(r);
        }
        write(replacement);
        SpeechPlaybackService.cancel(id);
        cancel(id, BASE); cancel(id, RETRY); notifications.cancel(id); notifications.cancel(-id);
        SpeechCache.prune(context);
        syncGuardian();
    }
    /** "稍后": drop the current occurrence and re-arm the same task later. */
    public void snooze(int id, long token, int minutes) throws JSONException {
        JSONArray rows = read();
        JSONObject r = find(rows, id);
        if (r == null || token <= 0 || r.optLong("activeOccurrence") != token || r.optBoolean("acknowledged")) return;
        long at = System.currentTimeMillis() + Math.max(1, Math.min(180, minutes)) * 60000L;
        r.put("acknowledged", true).put("retryAt", 0).put("muted", false).put("attempts", 0)
            .put("activeOccurrence", 0).put("nextTrigger", at).put("enabled", true);
        write(rows);
        cancel(id, BASE); cancel(id, RETRY);
        notifications.cancel(id); notifications.cancel(-id);
        SpeechPlaybackService.cancel(id);
        scheduleBase(r);
        trace("snoozed", id, at, "稍后 " + minutes + " 分钟");
        syncGuardian();
    }
    /** "静音本次": silence this occurrence, keep it unread and on screen. */
    public void mute(int id, long token) throws JSONException {
        JSONArray rows = read();
        JSONObject r = find(rows, id);
        if (r == null || token <= 0 || r.optLong("activeOccurrence") != token || r.optBoolean("acknowledged")) return;
        r.put("muted", true).put("retryAt", 0);
        write(rows);
        cancel(id, RETRY);
        SpeechPlaybackService.cancel(id);
        notify(r, token, false);
        trace("muted", id, token, "本次静音");
        syncGuardian();
    }
    public void acknowledge(int id, long token) throws JSONException {
        acknowledge(id, token, "应用内确认");
    }
    public void archive(int id) throws JSONException {
        JSONArray rows=read(); JSONObject r=find(rows,id); if(r==null) return;
        long generation=Math.max(System.currentTimeMillis(),Math.max(r.optLong("version"),prefs.getLong("generation",0))+1);
        prefs.edit().putLong("generation",generation).commit();
        r.put("archived",true).put("archivedAt",System.currentTimeMillis()).put("completed",true).put("enabled",false)
            .put("acknowledged",true).put("retryAt",0).put("nextTrigger",0).put("lastAck",System.currentTimeMillis())
            .put("version",generation);
        write(rows); cancel(id,BASE); cancel(id,RETRY); notifications.cancel(id); notifications.cancel(-id);
        SpeechPlaybackService.cancel(id); SpeechCache.prune(context); syncGuardian();
    }
    public void testAutoDelete(boolean enabled) { prefs.edit().putBoolean("testAutoDelete",enabled).commit(); }
    public void cleanupPrompts(boolean enabled) { prefs.edit().putBoolean("cleanupPrompts",enabled).commit(); }
    public void dismissed(int id,long token) throws JSONException {
        JSONObject before=find(read(),id);
        if(before==null || token<=0 || before.optLong("activeOccurrence")!=token || before.optBoolean("acknowledged")) return;
        acknowledge(id,token,"通知被划掉或系统移除");
        if(!unlocked || !prefs.getBoolean("cleanupPrompts",true)) return;
        JSONObject r=find(read(),id); if(r!=null) TaskCleanupNotification.show(context,r);
    }
    public void cleanupAction(Intent intent) throws JSONException {
        // A stale prompt must never delete or archive a newly edited/retriggered task.
        if(!unlocked || context.getSystemService(KeyguardManager.class).isKeyguardLocked()) return;
        int id=intent.getIntExtra("id",0); JSONObject r=find(read(),id);
        if(r==null || !r.optBoolean("acknowledged") || r.optLong("version")!=intent.getLongExtra("version",-1) ||
            r.optLong("activeOccurrence")!=intent.getLongExtra("token",0)) return;
        if(ARCHIVE.equals(intent.getAction())) archive(id);
        else if(DELETE.equals(intent.getAction())) delete(id);
    }
    public void acknowledge(int id, long token, String source) throws JSONException {
        JSONArray rows = read();
        JSONObject r = find(rows, id);
        if (r == null || token == 0 || r.optLong("activeOccurrence") != token) return;
        if(r.optBoolean("testReminder") && r.optBoolean("testAutoDelete") && "none".equals(r.optString("repeat"))) {
            delete(id); trace("test_auto_deleted",id,token,"自检任务已确认，自动清理"); return;
        }
        r.put("acknowledged", true);
        r.put("retryAt", 0);
        r.put("lastAck", System.currentTimeMillis());
        if ("none".equals(r.optString("repeat"))) {
            r.put("enabled", false); r.put("completed", true);
        }
        write(rows);
        cancel(id, RETRY);
        notifications.cancel(id);
        SpeechPlaybackService.cancel(id);
        trace("acknowledged", id, token, source); syncGuardian();
    }
    private long next(JSONObject r, long after) throws JSONException {
        Set<Integer> days = new HashSet<>();
        JSONArray array = r.optJSONArray("days");
        if (array != null) for (int i = 0; i < array.length(); i++) days.add(array.getInt(i));
        return Schedule.next(r.getInt("year"), r.getInt("month"), r.getInt("day"),
            r.getInt("hour"), r.getInt("minute"), r.optInt("second", 0), r.optInt("millisecond", 0), r.optString("repeat", "none"), days,
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
        if (r == null || !r.optBoolean("enabled", true) || r.optLong("version") != intent.getLongExtra("version", -1)) {
            trace("rejected", id, token, r == null ? "记录不存在" : !r.optBoolean("enabled", true) ? "记录未启用" : "版本已过期"); return;
        }
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
            notifications.cancel(-id);
            r.put("activeOccurrence", token);
            r.put("attempts", 0);
            r.put("acknowledged", false);
            r.put("muted", false);
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
        notify(r, token, true);
        syncGuardian();
    }
    public void restore(boolean wallClockChanged) throws JSONException { restore(wallClockChanged, "恢复排程"); }
    public void restore(boolean wallClockChanged, String reason) throws JSONException {
        restore(wallClockChanged, reason, true);
    }
    void restoreFromService() throws JSONException { restore(false, "可靠服务恢复排程", false); }
    private void restore(boolean wallClockChanged, String reason, boolean manageGuardian) throws JSONException {
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
        refreshNotifications();
        if (manageGuardian) syncGuardian();
    }
    /** Refresh existing notifications after credential unlock/upgrade without another alert or attempt. */
    public void refreshNotifications() throws JSONException {
        if (!unlocked) return;
        JSONArray rows = read();
        for (android.service.notification.StatusBarNotification posted : notifications.getActiveNotifications()) {
            JSONObject r = find(rows, posted.getId());
            if (r == null || r.optLong("activeOccurrence") == 0 || r.optBoolean("acknowledged")) continue;
            notify(r, r.getLong("activeOccurrence"), false);
        }
    }
    private String ensureChannel(JSONObject r) throws JSONException {
        return styles.ensure(r, unlocked);
    }
    @SuppressWarnings("deprecation")
    private void notify(JSONObject r, long token, boolean alert) throws JSONException {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            error("通知权限未开启，系统闹钟已触发但无法显示通知"); return;
        }
        // Muting one occurrence must not touch the shared style channel: that
        // would silence every reminder using the same style.
        boolean muted = r.optBoolean("muted", false);
        String channelId = muted ? styles.silentChannel() : ensureChannel(r);
        int id = r.getInt("id");
        Intent open = new Intent(context, MainActivity.class)
            .setAction("com.niceday.memo.OPEN").setData(Uri.parse("memo://open/" + id))
            .putExtra("reminderId", id).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent content = PendingIntent.getActivity(context, id, open,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        PendingIntent dismiss = intent(r, ACK, token);
        // SystemUI switches between the private payload and publicVersion on lock/unlock,
        // including while our process is dead. Only Direct Boot lacks the decrypted body.
        boolean bodyAvailable = unlocked && r.has("text");
        Notification publicVersion = new Notification.Builder(context, channelId)
            .setSmallIcon(com.niceday.memo.R.drawable.ic_notification)
            .setContentTitle("超级提醒").setContentText("有一条待办提醒 · 解锁后查看")
            .setVisibility(Notification.VISIBILITY_PUBLIC).build();
        Notification.Builder builder = new Notification.Builder(context, channelId)
            .setSmallIcon(com.niceday.memo.R.drawable.ic_notification)
            .setColor(0xFF7252F6).setContentTitle("超级提醒")
            .setContentText(bodyAvailable ? r.getString("text") : "有一条待办提醒 · 解锁后查看")
            .setSubText("第" + r.optInt("attempts") + "/" + r.optInt("totalCount") + "次 · 划掉后停止本轮提醒")
            .setVisibility(NotificationStyles.visibility(r)).setPublicVersion(publicVersion)
            .setPriority(NotificationStyles.importance(r) >= NotificationManager.IMPORTANCE_HIGH ? Notification.PRIORITY_MAX : Notification.PRIORITY_DEFAULT)
            .setCategory(Notification.CATEGORY_ALARM).setContentIntent(content)
            .setDeleteIntent(dismiss).setAutoCancel(false).setOnlyAlertOnce(!alert)
            .setWhen(r.optLong("lastFired", System.currentTimeMillis()));
        if (Build.VERSION.SDK_INT >= 29) builder.setAllowSystemGeneratedContextualActions(false);
        // Three actions, the three things people actually do when a reminder
        // lands: handled it, not now, stop making noise. Everything else still
        // needs the app, which is why there is no fourth.
        // "完成" reuses [dismiss] instead of building a second ACK intent: same
        // request code, same action, same data means FLAG_CANCEL_CURRENT would
        // cancel the record the notification's delete intent points at, and
        // swiping the notification away would then throw instead of acking.
        if (bodyAvailable) builder
            .addAction(new Notification.Action.Builder(Icon.createWithResource(context,
                com.niceday.memo.R.drawable.ic_action_done), "完成", dismiss).build())
            .addAction(new Notification.Action.Builder(Icon.createWithResource(context,
                com.niceday.memo.R.drawable.ic_action_snooze), "稍后10分钟", intent(r, SNOOZE, token)).build())
            .addAction(new Notification.Action.Builder(Icon.createWithResource(context,
                com.niceday.memo.R.drawable.ic_action_mute), "静音本次", intent(r, MUTE, token)).build());
        if (bodyAvailable) builder.setStyle(new Notification.BigTextStyle().bigText(r.getString("text")));
        notifications.notify(id, builder.build());
        if (alert && bodyAvailable && "banner".equals(r.optString("presentation", "banner"))) {
            if (!MainActivity.showReminder(r, token) && popupEnabled() && ReminderPopupService.mayDisplay(context)) {
                try { context.startForegroundService(new Intent(context, ReminderPopupService.class).putExtra("id", id).putExtra("token", token)); }
                catch (RuntimeException e) { popupError("系统限制亮屏卡片，请检查悬浮窗权限：" + e.getClass().getSimpleName()); }
            }
        }
        NotificationChannel actual = notifications.getNotificationChannel(channelId);
        trace(alert ? "notified" : "notification_refreshed", id, token,
            "importance=" + actual.getImportance() + ";bodyAvailable=" + bodyAvailable);
        // A muted occurrence sits on the deliberately quiet channel; reporting
        // "channel does not allow banners" for it would be noise, not a fix.
        if (!muted) {
            if (actual.getImportance() == NotificationManager.IMPORTANCE_NONE) error("此通知样式已被系统关闭，请打开对应的系统通知设置");
            else if (NotificationStyles.importance(r) == NotificationManager.IMPORTANCE_HIGH && actual.getImportance() < NotificationManager.IMPORTANCE_HIGH)
                error("系统通道未允许横幅，请打开这条提醒的系统通知设置");
        }
        if (alert && !muted && bodyAvailable && actual.getImportance() != NotificationManager.IMPORTANCE_NONE &&
            SpeechSettings.enabled(r, SpeechSettings.defaults(context))) SpeechPlaybackService.start(context, id, token);
        if (alert && r.optBoolean("wakeScreen", true)) {
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
            JSONObject defaults = SpeechSettings.defaults(context);
            r.put("speechMode", SpeechSettings.enabled(r, defaults) ? "on" : "off")
                .put("speechVoice", SpeechSettings.voice(r, defaults)).put("speechRate", SpeechSettings.rate(r, defaults))
                .put("speechNoiseScale", SpeechSettings.noise(r, defaults)).put("speechNoiseScaleW", SpeechSettings.noiseW(r, defaults));
            if((r.optBoolean("completed") || r.optBoolean("archived")) && r.optLong("activeOccurrence")>0)
                r.put("historyScheduledAt",r.getLong("activeOccurrence"));
            r.remove("notificationChannelId"); r.remove("notificationStyle"); portable.put(r);
        }
        return new JSONObject().put("format", "timed-memo").put("version", 1)
            .put("exportedAt", System.currentTimeMillis()).put("reminders", portable)
            .put("defaults", new JSONObject(prefs.getString("defaults", "{}")))
            .put("voiceGroups",VoiceGroups.read(context)).toString(2);
    }
    public int importBackup(String source) throws JSONException {
        if (!unlocked) throw new IllegalStateException("请先解锁手机");
        JSONArray imported = BackupCodec.decode(source);
        JSONArray combined=VoiceGroups.read(context);
        JSONArray incoming=VoiceGroups.validate(new JSONObject(source).optJSONArray("voiceGroups")==null ? new JSONArray() : new JSONObject(source).getJSONArray("voiceGroups"));
        java.util.Map<String,String> groupIds=new java.util.HashMap<>();
        for(int i=0;i<incoming.length();i++) {
            JSONObject g=new JSONObject(incoming.getJSONObject(i).toString());
            String old=g.getString("id"), replacement=old;
            if(VoiceGroups.members(combined,old)!=null) replacement=java.util.UUID.randomUUID().toString();
            groupIds.put(old,replacement); g.put("id",replacement); combined.put(g);
        }
        VoiceGroups.validate(combined);
        JSONArray rows = read();
        int id = prefs.getInt("nextId", 1);
        for (int i = 0; i < rows.length(); i++) id = Math.max(id, rows.getJSONObject(i).getInt("id") + 1);
        long generation = Math.max(System.currentTimeMillis(), prefs.getLong("generation", 0) + 1);
        for (int i = 0; i < imported.length(); i++) {
            JSONObject r = imported.getJSONObject(i);
            String oldGroup=r.optString("speechRandomGroup","");
            if(groupIds.containsKey(oldGroup)) r.put("speechRandomGroup",groupIds.get(oldGroup));
            else if(!oldGroup.isEmpty() && VoiceGroups.members(combined,oldGroup)==null) r.put("speechRandomGroup","");
            long n = next(r, System.currentTimeMillis());
            boolean enabled = r.optBoolean("enabled", true) && n > 0 && !r.optBoolean("completed") && !r.optBoolean("archived");
            r.put("id", id++).put("version", generation++).put("enabled", enabled)
                .put("nextTrigger", enabled ? n : 0).put("activeOccurrence", 0).put("attempts", 0)
                .put("retryAt", 0).put("acknowledged", false)
                .put("completed", r.optBoolean("completed") || ("none".equals(r.optString("repeat")) && n == 0))
                .put("ringtone", "");
            r.remove("notificationChannelId"); r.remove("notificationStyle");
            VoiceCatalog.resolve(context,r,combined);
            ensureChannel(r);
            rows.put(r);
        }
        // Commit task/group references together; the existing mirror writer stays unchanged.
        if(!prefs.edit().putString("reminders",rows.toString()).putString("voiceGroups",combined.toString())
            .putInt("nextId",id).putLong("generation",generation).putInt("schema",2).commit())
            throw new IllegalStateException("导入保存失败，请检查存储空间");
        write(rows);
        for (int i = rows.length() - imported.length(); i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i); ensureChannel(r); scheduleBase(r);
        }
        syncGuardian();
        return imported.length();
    }
    public int createSelfTest(int seconds) throws JSONException {
        int id=createTest(seconds); JSONArray rows=read(); JSONObject r=find(rows,id);
        r.put("testReminder",true).put("testAutoDelete",prefs.getBoolean("testAutoDelete",true));
        write(rows); return id;
    }
    public int createTest(int seconds) throws JSONException { return createTest(seconds, 1); }
    public int createTest(int seconds, int totalCount) throws JSONException {
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
            .put("speechMode", defaults.optString("speechMode", "off")).put("speechVoice", defaults.optString("speechVoice", SpeechSettings.VOICE))
            .put("speechRate", defaults.optDouble("speechRate", 1))
            .put("speechNoiseScale", defaults.optDouble("speechNoiseScale", .6)).put("speechNoiseScaleW", defaults.optDouble("speechNoiseScaleW", .668)).put("speechHideLocked", defaults.optBoolean("speechHideLocked", true))
            .put("speechRepeat", defaults.optBoolean("speechRepeat", true))
            .put("intervalMinutes", 5).put("totalCount", Math.max(1, Math.min(20, totalCount)));
        save(config.toString());
        int id = prefs.getInt("nextId", 1) - 1;
        JSONArray rows = read(); JSONObject r = find(rows, id);
        long stamp = System.currentTimeMillis() + seconds * 1000L;
        Calendar actual = Calendar.getInstance(); actual.setTimeInMillis(stamp);
        r.put("year", actual.get(Calendar.YEAR)).put("month", actual.get(Calendar.MONTH) + 1)
            .put("day", actual.get(Calendar.DAY_OF_MONTH)).put("hour", actual.get(Calendar.HOUR_OF_DAY))
            .put("minute", actual.get(Calendar.MINUTE)).put("second", actual.get(Calendar.SECOND))
            .put("millisecond", actual.get(Calendar.MILLISECOND)).put("nextTrigger", stamp);
        write(rows); cancel(id, BASE); scheduleBase(r); return id;
    }
}
