package com.niceday.memo;

import android.content.Context;
import org.json.*;
import java.io.*;
import java.util.*;

/** Private durable audio. Flutter synthesizes ahead of time; alarm delivery only reads WAVs. */
final class SpeechCache {
    static final long LIMIT = 128L * 1024 * 1024;
    private static final Set<String> pending = new HashSet<>();
    private static final Map<String, String> errors = new HashMap<>();
    static File directory(Context c) { return new File(c.getFilesDir(), "speech-audio"); }
    static File file(Context c, String text, JSONObject row, JSONObject defaults) {
        return new File(directory(c), SpeechSettings.cacheKey(text, SpeechSettings.voice(row, defaults), SpeechSettings.rate(row, defaults)) + ".wav");
    }
    static boolean ready(File file) {
        if (!file.isFile() || file.length() <= 44) return false;
        try (RandomAccessFile input = new RandomAccessFile(file, "r")) {
            if (input.readInt() != 0x52494646) return false;
            input.seek(8); return input.readInt() == 0x57415645;
        } catch (IOException e) { return false; }
    }
    static String state(Context c, JSONObject row, JSONObject defaults) {
        if (!SpeechSettings.enabled(row, defaults)) return "off";
        String key = file(c, row.optString("text"), row, defaults).getName();
        return ready(new File(directory(c), key)) ? "ready" : pending.contains(key) ? "preparing" : errors.containsKey(key) ? "error" : "missing";
    }
    static JSONArray jobs(Context c, boolean retry) throws Exception {
        if (!directory(c).isDirectory() && !directory(c).mkdirs()) throw new IOException("无法建立语音目录");
        if (retry) errors.clear();
        prune(c);
        JSONObject defaults = SpeechSettings.defaults(c);
        JSONArray rows = new JSONArray(c.getSharedPreferences("memo", 0).getString("reminders", "[]"));
        JSONArray jobs = new JSONArray(); Set<String> seen = new HashSet<>();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.getJSONObject(i);
            if (!row.optBoolean("enabled", true) || !SpeechSettings.enabled(row, defaults)) continue;
            // Generic audio is always available before the private body is synthesized.
            for (String text : Arrays.asList(SpeechSettings.GENERIC, row.optString("text"))) {
                File target = file(c, text, row, defaults);
                if (ready(target) || !seen.add(target.getName()) || errors.containsKey(target.getName())) continue;
                pending.add(target.getName());
                jobs.put(new JSONObject().put("key", target.getName()).put("text", text)
                    .put("sid", Integer.parseInt(SpeechSettings.voice(row, defaults))).put("rate", SpeechSettings.rate(row, defaults))
                    .put("path", target.getPath() + ".part"));
            }
        }
        return jobs;
    }
    static JSONObject previewJob(Context c, JSONObject config) throws Exception {
        if (!directory(c).isDirectory() && !directory(c).mkdirs()) throw new IOException("无法建立语音目录");
        JSONObject defaults = SpeechSettings.defaults(c);
        String text = "这是备忘录语音试听，请记得按时完成待办事项。";
        File target = file(c, text, config, defaults);
        if (!ready(target)) pending.add(target.getName());
        return new JSONObject().put("key", target.getName()).put("text", text)
            .put("sid", Integer.parseInt(SpeechSettings.voice(config, defaults))).put("rate", SpeechSettings.rate(config, defaults))
            .put("ready", ready(target)).put("path", target.getPath() + ".part");
    }
    static void finish(Context c, String key, String error) throws Exception {
        if (!key.matches("[0-9a-f]{64}\\.wav") || !pending.contains(key)) throw new IllegalArgumentException("语音缓存任务已失效");
        File target = new File(directory(c), key), temporary = new File(target.getPath() + ".part");
        try {
            if (error.isEmpty()) {
                if (!ready(temporary) || bytes(c) > LIMIT || !temporary.renameTo(target)) throw new IOException("语音文件无效或缓存空间不足");
                errors.remove(key);
            } else errors.put(key, "语音准备失败");
        } catch (Exception e) { errors.put(key, "语音保存失败"); throw e; }
        finally {
            temporary.delete(); pending.remove(key);
            c.getSharedPreferences("memo", 0).edit().putString("speechLastError", errors.isEmpty() ? "" : "部分语音未就绪，将按铃声／振动设置备用提醒")
                .putLong("speechChanged", System.currentTimeMillis()).apply();
        }
    }
    static long bytes(Context c) {
        File[] files = directory(c).listFiles(); long size = 0;
        if (files != null) for (File file : files) size += file.length();
        return size;
    }
    static void prune(Context c) {
        try {
            Set<String> keep = new HashSet<>(); JSONObject defaults = SpeechSettings.defaults(c);
            JSONArray rows = new JSONArray(c.getSharedPreferences("memo", 0).getString("reminders", "[]"));
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = rows.getJSONObject(i);
                if (SpeechSettings.enabled(row, defaults)) {
                    keep.add(file(c, row.optString("text"), row, defaults).getName());
                    keep.add(file(c, SpeechSettings.GENERIC, row, defaults).getName());
                }
            }
            File[] files = directory(c).listFiles();
            if (files != null) for (File file : files) {
                String name = file.getName();
                if ((name.endsWith(".wav") && !keep.contains(name) && !pending.contains(name)) ||
                    (name.endsWith(".part") && !pending.contains(name.substring(0, name.length() - 5)))) file.delete();
            }
        } catch (JSONException ignored) {}
    }
    static JSONObject status(Context c) throws JSONException {
        return new JSONObject().put("engine", "AISHELL-3 VITS · 174音色 · 8kHz")
            .put("speakerCount", 174).put("pending", pending.size()).put("cacheBytes", bytes(c))
            .put("error", c.getSharedPreferences("memo", 0).getString("speechLastError", ""));
    }
}
