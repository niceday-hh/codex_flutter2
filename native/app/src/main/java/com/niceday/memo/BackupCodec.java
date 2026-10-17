package com.niceday.memo;

import org.json.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Strict bounded validation before any imported data touches persistent storage. */
public final class BackupCodec {
    public static final int MAX_BYTES = 8 * 1024 * 1024;
    private BackupCodec() {}
    public static void validateReminder(JSONObject r) throws JSONException {
        String text = r.optString("text").trim();
        if (text.isEmpty() || text.length() > 2000) throw new IllegalArgumentException("提醒内容须为1至2000字");
        Calendar date = Calendar.getInstance(); date.clear(); date.setLenient(false);
        date.set(r.getInt("year"), r.getInt("month") - 1, r.getInt("day"), r.getInt("hour"), r.getInt("minute"), r.optInt("second", 0));
        date.set(Calendar.MILLISECOND, r.optInt("millisecond", 0));
        date.getTimeInMillis();
        if (r.getInt("year") < 1970 || r.getInt("year") > 2200) throw new IllegalArgumentException("日期超出支持范围");
        String repeat = r.optString("repeat", "none");
        if (!Arrays.asList("none", "daily", "weekly").contains(repeat)) throw new IllegalArgumentException("不支持的重复方式");
        JSONArray days = r.optJSONArray("days");
        if (days == null) { days = new JSONArray(); r.put("days", days); }
        if ("weekly".equals(repeat) && days.length() == 0) throw new IllegalArgumentException("请选择重复星期");
        Set<Integer> unique = new HashSet<>();
        for (int i = 0; i < days.length(); i++) {
            int day = days.getInt(i);
            if (day < 1 || day > 7 || !unique.add(day)) throw new IllegalArgumentException("重复星期无效");
        }
        int interval = r.optInt("intervalMinutes", 5), total = r.optInt("totalCount", 3);
        if (interval < 1 || interval > 1440 || total < 1 || total > 20) throw new IllegalArgumentException("重提醒设置无效");
        r.put("intervalMinutes", interval).put("totalCount", total);
        validateStyle(r);
        SpeechSettings.validate(r, false);
        for(String field:Arrays.asList("testReminder","testAutoDelete"))
            if(r.has(field) && !(r.get(field) instanceof Boolean)) throw new IllegalArgumentException("测试清理设置无效");
        if(r.has("archived") && !(r.get("archived") instanceof Boolean)) throw new IllegalArgumentException("归档状态无效");
        for (String field : Arrays.asList("archivedAt","lastAck")) {
            if (!r.has(field)) continue;
            Object value=r.get(field);
            if (!(value instanceof Integer || value instanceof Long) || ((Number)value).longValue()<0 || ((Number)value).longValue()>8640000000000000L)
                throw new IllegalArgumentException("整理时间无效");
        }
    }
    public static void validateStyle(JSONObject r) throws JSONException {
        if (!Arrays.asList("system", "off", "once", "twice", "three", "strong").contains(r.optString("vibration", "three")))
            throw new IllegalArgumentException("振动模式无效");
        if (!Arrays.asList("banner", "drawer").contains(r.optString("presentation", "banner")))
            throw new IllegalArgumentException("通知展示方式无效");
        if (!Arrays.asList("private", "hidden").contains(r.optString("lockscreen", "private")))
            throw new IllegalArgumentException("锁屏显示方式无效");
        for (String field : Arrays.asList("sound", "wakeScreen")) {
            if (r.has(field) && !(r.get(field) instanceof Boolean)) throw new IllegalArgumentException("提醒开关无效");
        }
        r.put("sound", r.optBoolean("sound", true)).put("wakeScreen", r.optBoolean("wakeScreen", true))
            .put("vibration", r.optString("vibration", "three")).put("ringtone", r.optString("ringtone", ""))
            .put("presentation", r.optString("presentation", "banner")).put("lockscreen", r.optString("lockscreen", "private"));
    }
    public static JSONArray decode(String source) throws JSONException {
        if (source.getBytes(StandardCharsets.UTF_8).length > MAX_BYTES) throw new IllegalArgumentException("备份文件不能超过8MB");
        JSONObject root = new JSONObject(source);
        if (!"timed-memo".equals(root.optString("format")) || root.optInt("version") != 1)
            throw new IllegalArgumentException("不是支持的备忘录备份文件");
        JSONArray rows = root.getJSONArray("reminders");
        if (rows.length() > 1000) throw new IllegalArgumentException("一次最多导入1000条提醒");
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row=rows.getJSONObject(i);
            boolean legacy=!"voine-vits-mnn-v1".equals(row.optString("speechModel"));
            validateReminder(row);
            if (legacy && !row.optString("speechVoice").isEmpty()) row.put("speechVoice",SpeechSettings.VOICE);
        }
        return rows;
    }
}
