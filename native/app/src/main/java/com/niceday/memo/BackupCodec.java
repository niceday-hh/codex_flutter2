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
        date.set(r.getInt("year"), r.getInt("month") - 1, r.getInt("day"), r.getInt("hour"), r.getInt("minute"), 0);
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
        if (!Arrays.asList("system", "off", "once", "twice", "three", "strong").contains(r.optString("vibration", "three")))
            throw new IllegalArgumentException("振动模式无效");
    }
    public static JSONArray decode(String source) throws JSONException {
        if (source.getBytes(StandardCharsets.UTF_8).length > MAX_BYTES) throw new IllegalArgumentException("备份文件不能超过8MB");
        JSONObject root = new JSONObject(source);
        if (!"timed-memo".equals(root.optString("format")) || root.optInt("version") != 1)
            throw new IllegalArgumentException("不是支持的备忘录备份文件");
        JSONArray rows = root.getJSONArray("reminders");
        if (rows.length() > 1000) throw new IllegalArgumentException("一次最多导入1000条提醒");
        for (int i = 0; i < rows.length(); i++) validateReminder(rows.getJSONObject(i));
        return rows;
    }
}
