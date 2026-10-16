package com.niceday.memo;

import android.app.*;
import android.content.*;
import android.media.*;
import android.net.Uri;
import android.os.VibrationEffect;
import android.os.Vibrator;
import org.json.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** Notification settings are shared by effective style, never by reminder ID. */
final class NotificationStyles {
    private final Context context;
    private final NotificationManager manager;
    private final SharedPreferences runtime;
    NotificationStyles(Context context, NotificationManager manager, SharedPreferences runtime) {
        this.context = context; this.manager = manager; this.runtime = runtime;
    }
    static int importance(JSONObject r) {
        return "drawer".equals(r.optString("presentation"))
            ? NotificationManager.IMPORTANCE_DEFAULT : NotificationManager.IMPORTANCE_HIGH;
    }
    static int visibility(JSONObject r) {
        return "hidden".equals(r.optString("lockscreen")) ? Notification.VISIBILITY_SECRET : Notification.VISIBILITY_PRIVATE;
    }
    private boolean sound(JSONObject r) {
        return r.optBoolean("sound", true) && !SpeechSettings.enabled(r, SpeechSettings.defaults(context));
    }
    private Uri ringtone(JSONObject r) {
        return r.optString("ringtone").isEmpty() ? RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            : Uri.parse(r.optString("ringtone"));
    }
    private String key(JSONObject r) throws JSONException {
        JSONArray values = new JSONArray().put(sound(r)).put(r.optString("vibration", "three"))
            .put(sound(r) ? String.valueOf(ringtone(r)) : "")
            .put(r.optString("presentation", "banner")).put(r.optString("lockscreen", "private"));
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(values.toString().getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte b : digest) hex.append(Character.forDigit((b >> 4) & 15, 16)).append(Character.forDigit(b & 15, 16));
            return hex.toString();
        } catch (java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
    private boolean owned(String id) { return id.startsWith("memo_v2_") || id.startsWith("memo_v3_"); }
    private String legacyId(JSONObject r) {
        return "memo_v2_" + Integer.toHexString((sound(r) + ":" + r.optString("vibration", "three") + ":" + ringtone(r)).hashCode());
    }
    static String vibrationName(String value) {
        return switch (value) {
            case "off" -> "不振动"; case "system" -> "系统振动"; case "once" -> "振动一次";
            case "twice" -> "振动两次"; case "strong" -> "长振动两次"; default -> "振动三次";
        };
    }
    private String ringtoneName(JSONObject r) {
        if (SpeechSettings.enabled(r, SpeechSettings.defaults(context))) return "语音播报";
        if (!sound(r)) return "静音";
        if (r.optString("ringtone").isEmpty()) return "默认铃声";
        try {
            Ringtone tone = RingtoneManager.getRingtone(context, ringtone(r));
            if (tone != null) return "铃声：" + tone.getTitle(context);
        } catch (Exception ignored) {}
        return "自选铃声";
    }
    private String name(JSONObject r) {
        return ("drawer".equals(r.optString("presentation")) ? "仅通知栏" : "横幅提醒") + " · "
            + ("hidden".equals(r.optString("lockscreen")) ? "锁屏不显示" : "锁屏隐藏正文") + " · "
            + vibrationName(r.optString("vibration", "three")) + " · " + ringtoneName(r);
    }
    static long[] pattern(String vibration) {
        return switch (vibration) {
            case "once" -> new long[]{0, 250}; case "twice" -> new long[]{0, 250, 200, 250};
            case "strong" -> new long[]{0, 700, 250, 700}; default -> new long[]{0, 200, 200, 200, 200, 200};
        };
    }
    static void preview(Context context, String mode) {
        if (!Arrays.asList("once", "twice", "three", "strong").contains(mode))
            throw new IllegalArgumentException("系统默认节奏请使用15秒通知测试");
        Vibrator vibrator = context.getSystemService(Vibrator.class);
        if (vibrator == null || !vibrator.hasVibrator()) throw new IllegalStateException("此设备没有可用振动器");
        vibrator.vibrate(VibrationEffect.createWaveform(pattern(mode), -1), new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION).build());
    }
    private String actualVibration(NotificationChannel c) {
        if (!c.shouldVibrate()) return "系统实际：振动已关闭";
        long[] actual = c.getVibrationPattern();
        if (actual == null || actual.length == 0) return "系统实际：默认或系统效果（次数由系统决定）";
        int pulses = 0;
        for (int i = 1; i < actual.length; i += 2) if (actual[i] > 0) pulses++;
        return "系统已记录：" + pulses + " 段振动（硬件效果请实测）";
    }
    String ensure(JSONObject r, boolean unlocked) throws JSONException {
        // The mirror carries only the channel ID/hash, not a custom ringtone URI.
        String saved = r.optString("notificationChannelId");
        if (!unlocked && owned(saved) && manager.getNotificationChannel(saved) != null) return saved;
        BackupCodec.validateStyle(r);
        String hash = key(r), registry = "notification-style-" + hash;
        String id = runtime.getString(registry, "");
        if (!owned(id) || manager.getNotificationChannel(id) == null) {
            String legacy = legacyId(r);
            // Reuse v0.2 default-display channels so user changes survive upgrading.
            boolean useLegacy = "banner".equals(r.getString("presentation")) && "private".equals(r.getString("lockscreen"))
                && manager.getNotificationChannel(legacy) != null;
            id = useLegacy ? legacy : "memo_v3_" + hash;
        }
        String vibration = r.optString("vibration", "three");
        NotificationChannel channel = new NotificationChannel(id, name(r), importance(r));
        channel.setDescription("相同样式的备忘共用此系统设置；手动划掉通知确认本次提醒");
        channel.setLockscreenVisibility(visibility(r));
        channel.enableVibration(!"off".equals(vibration));
        if (!"off".equals(vibration) && !"system".equals(vibration)) channel.setVibrationPattern(pattern(vibration));
        channel.setSound(sound(r) ? ringtone(r) : null, new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
        // Recreating a channel updates its name, but does not overwrite user-owned behavior.
        manager.createNotificationChannel(channel);
        if (!id.equals(runtime.getString(registry, ""))) runtime.edit().putString(registry, id).commit();
        r.put("notificationChannelId", id).put("notificationStyle", hash);
        return id;
    }
    private JSONObject describe(JSONObject r, String id) throws JSONException {
        NotificationChannel c = manager.getNotificationChannel(id);
        int actualVisibility = c.getLockscreenVisibility();
        boolean knownVisibility = actualVisibility == Notification.VISIBILITY_PRIVATE || actualVisibility == Notification.VISIBILITY_PUBLIC || actualVisibility == Notification.VISIBILITY_SECRET;
        boolean changed = c.getImportance() != importance(r) || (c.getSound() != null) != sound(r)
            || c.shouldVibrate() != !"off".equals(r.optString("vibration", "three"))
            || (knownVisibility && actualVisibility != visibility(r));
        boolean customVibration = !"off".equals(r.optString("vibration")) && !"system".equals(r.optString("vibration"));
        boolean vibrationMismatch = c.shouldVibrate() != !"off".equals(r.optString("vibration"))
            || (customVibration && !Arrays.equals(c.getVibrationPattern(), pattern(r.optString("vibration"))));
        changed |= vibrationMismatch;
        if (sound(r) && !Objects.equals(c.getSound(), ringtone(r))) changed = true;
        return new JSONObject().put("id", id).put("name", name(r)).put("count", 0).put("isDefault", false)
            .put("importance", c.getImportance()).put("systemOverridden", changed)
            .put("vibrationMismatch", vibrationMismatch).put("actualVibration", actualVibration(c))
            .put("actualVibrationPattern", c.getVibrationPattern() == null ? JSONObject.NULL : new JSONArray(c.getVibrationPattern()))
            .put("presentation", r.optString("presentation", "banner")).put("lockscreen", r.optString("lockscreen", "private"));
    }
    JSONArray groups(JSONArray rows, JSONObject defaults, boolean unlocked) throws JSONException {
        Map<String, JSONObject> groups = new LinkedHashMap<>();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.getJSONObject(i);
            BackupCodec.validateStyle(r);
            String key = key(r);
            JSONObject group = groups.get(key);
            if (group == null) { group = describe(r, ensure(r, unlocked)); groups.put(key, group); }
            group.put("count", group.getInt("count") + 1);
        }
        BackupCodec.validateStyle(defaults);
        String key = key(defaults);
        JSONObject group = groups.get(key);
        if (group == null) { group = describe(defaults, ensure(defaults, unlocked)); groups.put(key, group); }
        group.put("isDefault", true);
        JSONArray result = new JSONArray();
        for (JSONObject item : groups.values()) result.put(item);
        return result;
    }
    int hiddenCount(JSONArray groups) throws JSONException {
        Set<String> used = new HashSet<>();
        for (int i = 0; i < groups.length(); i++) used.add(groups.getJSONObject(i).getString("id"));
        int hidden = 0;
        for (NotificationChannel c : manager.getNotificationChannels()) if (owned(c.getId()) && !used.contains(c.getId())) hidden++;
        return hidden;
    }
}
