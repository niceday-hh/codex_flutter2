package com.niceday.memo;

import android.content.Context;
import org.json.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** Portable settings only. Cache names are derived locally and never trusted from backup. */
public final class SpeechSettings {
    public static final String VOICE = "0";
    public static final String GENERIC = "你有一条待办提醒，请解锁后查看";
    private SpeechSettings() {}
    public static JSONObject defaults(Context c) {
        if (!c.getSystemService(android.os.UserManager.class).isUserUnlocked()) return new JSONObject();
        try { return new JSONObject(c.getSharedPreferences("memo", 0).getString("defaults", "{}")); }
        catch (JSONException e) { return new JSONObject(); }
    }
    public static boolean enabled(JSONObject row, JSONObject defaults) {
        return switch (row.optString("speechMode", "off")) {
            case "on" -> true;
            case "inherit" -> "on".equals(defaults.optString("speechMode", "off"));
            default -> false;
        };
    }
    public static String voice(JSONObject row, JSONObject defaults) {
        String value = row.optString("speechVoice", "");
        return value.isEmpty() ? defaults.optString("speechVoice", VOICE) : value;
    }
    public static double rate(JSONObject row, JSONObject defaults) {
        double value = row.optDouble("speechRate", 0);
        return value == 0 ? defaults.optDouble("speechRate", 1.0) : value;
    }
    public static boolean hideLocked(JSONObject row, JSONObject defaults) {
        return row.has("speechHideLocked") ? row.optBoolean("speechHideLocked", true) : defaults.optBoolean("speechHideLocked", true);
    }
    public static void validate(JSONObject r, boolean defaults) throws JSONException {
        for (String field : Arrays.asList("speechMode", "speechVoice"))
            if (r.has(field) && !(r.get(field) instanceof String)) throw new IllegalArgumentException("语音参数类型无效");
        if (r.has("speechRate") && !(r.get("speechRate") instanceof Number)) throw new IllegalArgumentException("语速参数无效");
        String mode = r.optString("speechMode", "off"); // Existing reminders retain their original behavior.
        if (!Arrays.asList("inherit", "on", "off").contains(mode) || (defaults && "inherit".equals(mode)))
            throw new IllegalArgumentException("语音播报设置无效");
        String voice = r.optString("speechVoice", defaults ? VOICE : "");
        if (!voice.isEmpty() && (!voice.matches("[0-9]{1,3}") || Integer.parseInt(voice) > 173)) throw new IllegalArgumentException("音色编号须为0至173");
        double rate = r.optDouble("speechRate", defaults ? 1 : 0);
        if (!Double.isFinite(rate) || (rate != 0 && (rate < 0.8 || rate > 1.3)) || (defaults && rate == 0))
            throw new IllegalArgumentException("语速须为0.8至1.3倍");
        for (String field : Arrays.asList("speechHideLocked", "speechRepeat"))
            if (r.has(field) && !(r.get(field) instanceof Boolean)) throw new IllegalArgumentException("语音隐私开关无效");
        r.put("speechMode", mode).put("speechVoice", voice).put("speechRate", rate);
        if (!r.has("speechHideLocked")) r.put("speechHideLocked", true);
        if (!r.has("speechRepeat")) r.put("speechRepeat", true);
    }
    public static String cacheKey(String text, String voice, double rate) {
        try {
            byte[] bytes = MessageDigest.getInstance("SHA-256").digest(
                ("aishell3-8k-v1\n" + voice + "\n" + Math.round(rate * 100) + "\n" + text).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte b : bytes) hex.append(String.format(Locale.ROOT, "%02x", b & 255));
            return hex.toString();
        } catch (java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
}
