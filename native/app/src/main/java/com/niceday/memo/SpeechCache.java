package com.niceday.memo;

import android.content.Context;
import org.json.*;
import java.io.*;
import java.util.*;

/** Private durable audio. Flutter synthesizes ahead of time; alarm delivery only reads WAVs. */
final class SpeechCache {
    static final long LIMIT = 128L * 1024 * 1024;
    private static final Set<String> pending = Collections.synchronizedSet(new HashSet<>());
    private static final Map<String, String> errors = new HashMap<>();
    private static final class Lease {
        final String key, name, expected; final Set<String> keys = new HashSet<>();
        final int id; final long seed, created = android.os.SystemClock.elapsedRealtime();
        Lease(String key, String name, int id, long seed, String expected) {
            this.key = key; this.name = name; this.id = id; this.seed = seed; this.expected = expected; keys.add(key);
        }
    }
    private static final Map<String, Lease> leases = new HashMap<>();
    static synchronized void releaseAudio(String token) { leases.remove(token); }
    private static synchronized Lease lease(String token) {
        Lease held = leases.get(token);
        if (held == null) throw new IllegalArgumentException("音频操作已失效，请重新试听或保存");
        return held;
    }
    static File leasedAudio(Context c, String token) throws IOException {
        File file = new File(directory(c), lease(token).key);
        if (!ready(file)) throw new IOException("提醒音频尚未准备完成，请重试");
        return file;
    }
    static boolean audioReady(Context c, String token) {
        for (String key : lease(token).keys) if (!ready(new File(directory(c), key))) return false;
        return true;
    }
    static String audioName(String token) { return lease(token).name; }
    static synchronized JSONObject reminderAudioJob(Context c, int id) throws Exception { return reminderAudioJob(c, id, false); }
    static synchronized JSONObject candidateAudioJob(Context c, int id) throws Exception { return reminderAudioJob(c, id, true); }
    private static JSONObject reminderAudioJob(Context c, int id, boolean candidate) throws Exception {
        JSONArray rows = new JSONArray(c.getSharedPreferences("memo", 0).getString("reminders", "[]"));
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.getJSONObject(i);
            if (row.optInt("id") != id || id <= 0) continue;
            String text = row.optString("text");
            if (text.trim().isEmpty()) throw new IllegalArgumentException("提醒正文为空");
            String expected = candidate ? file(c, text, row, SpeechSettings.defaults(c)).getName() : null;
            JSONObject snapshot = new JSONObject(row.toString());
            if (candidate) {
                int seed; do { seed = SpeechSettings.newSeed(); } while (seed == SpeechSettings.seed(row));
                snapshot.put("speechSeed", seed);
            }
            JSONObject job = textJob(c, text, snapshot);
            String token = UUID.randomUUID().toString(), name = "reminder-" + id + "-voice-" + job.getInt("sid") + ".wav";
            Lease held = new Lease(job.getString("key"), name, id, SpeechSettings.seed(snapshot), expected);
            if (candidate) {
                JSONObject generic = textJob(c, SpeechSettings.GENERIC, snapshot);
                if (held.keys.add(generic.getString("key"))) job.put("companions", new JSONArray().put(generic));
            }
            leases.put(token, held);
            return job.put("lease", token).put("filename", name).put("reminderId", id);
        }
        throw new IllegalArgumentException("这条提醒已不存在，请返回列表刷新");
    }
    /** Commit a prepared candidate without reactivating or acknowledging the task. */
    static synchronized void selectAudio(Context c, String token) throws Exception {
        Lease held = lease(token);
        if (held.expected == null || !audioReady(c, token)) throw new IllegalStateException("新版本尚未准备好");
        android.content.SharedPreferences prefs = c.getSharedPreferences("memo", 0);
        JSONArray rows = new JSONArray(prefs.getString("reminders", "[]"));
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.getJSONObject(i);
            if (row.optInt("id") != held.id) continue;
            if (!file(c, row.optString("text"), row, SpeechSettings.defaults(c)).getName().equals(held.expected))
                throw new IllegalStateException("提醒内容或语音设置已更改，请重新换一版");
            row.put("speechSeed", held.seed);
            if (!prefs.edit().putString("reminders", rows.toString()).commit()) throw new IOException("无法保存音频版本");
            return;
        }
        throw new IllegalStateException("这条提醒已不存在");
    }
    static boolean pending(String key) { return key != null && key.matches("[0-9a-f]{64}\\.wav") && pending.contains(key); }
    static File directory(Context c) { return new File(c.getFilesDir(), "speech-audio"); }
    static File file(Context c, String text, JSONObject row, JSONObject defaults) {
        return new File(directory(c), SpeechSettings.cacheKey(text, SpeechSettings.voice(row, defaults), SpeechSettings.rate(row, defaults), SpeechSettings.noise(row, defaults), SpeechSettings.noiseW(row, defaults), SpeechSettings.seed(row)) + ".wav");
    }
    static boolean ready(File file) {
        if (!file.isFile() || file.length() <= 44) return false;
        try (RandomAccessFile input = new RandomAccessFile(file, "r")) {
            if (input.readInt() != 0x52494646) return false;
            if (Integer.reverseBytes(input.readInt()) != file.length() - 8 || input.readInt() != 0x57415645 || input.readInt() != 0x666d7420) return false;
            if (Integer.reverseBytes(input.readInt()) != 16 || Short.reverseBytes(input.readShort()) != 1 || Short.reverseBytes(input.readShort()) != 1) return false;
            if (Integer.reverseBytes(input.readInt()) != 22050 || Integer.reverseBytes(input.readInt()) != 44100) return false;
            input.seek(32);
            if (Short.reverseBytes(input.readShort()) != 2 || Short.reverseBytes(input.readShort()) != 16 || input.readInt() != 0x64617461) return false;
            return Integer.reverseBytes(input.readInt()) == file.length() - 44;
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
                jobs.put(textJob(c, text, row));
            }
        }
        return jobs;
    }
    static JSONObject previewJob(Context c, JSONObject config) throws Exception {
        return textJob(c, "这是备忘录语音试听，请记得按时完成待办事项。", new JSONObject(config.toString()).put("speechSeed", SpeechSettings.newSeed()));
    }
    private static JSONObject textJob(Context c, String text, JSONObject config) throws Exception {
        if (!directory(c).isDirectory() && !directory(c).mkdirs()) throw new IOException("无法建立语音目录");
        JSONObject defaults = SpeechSettings.defaults(c);
        File target = file(c, text, config, defaults);
        if (!ready(target)) pending.add(target.getName());
        return new JSONObject().put("key", target.getName()).put("text", text)
            .put("sid", Integer.parseInt(SpeechSettings.voice(config, defaults))).put("rate", SpeechSettings.rate(config, defaults))
            .put("noise", SpeechSettings.noise(config, defaults)).put("noiseW", SpeechSettings.noiseW(config, defaults)).put("seed", SpeechSettings.seed(config))
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
            Set<String> keep = new HashSet<>();
            synchronized (SpeechCache.class) {
                long now = android.os.SystemClock.elapsedRealtime();
                leases.values().removeIf(held -> now - held.created > 3600000L);
                for (Lease held : leases.values()) keep.addAll(held.keys);
            }
            JSONObject defaults = SpeechSettings.defaults(c);
            JSONArray rows = new JSONArray(c.getSharedPreferences("memo", 0).getString("reminders", "[]"));
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = rows.getJSONObject(i);
                // Saved selections remain available for history preview/export too.
                keep.add(file(c, row.optString("text"), row, defaults).getName());
                keep.add(file(c, SpeechSettings.GENERIC, row, defaults).getName());
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
        return new JSONObject().put("engine", "VITS-MNN · 804个音色条目 · 22.05kHz")
            .put("speakerCount", 804).put("pending", pending.size()).put("cacheBytes", bytes(c))
            .put("error", c.getSystemService(android.os.UserManager.class).isUserUnlocked() ? c.getSharedPreferences("memo", 0).getString("speechLastError", "") : "");
    }
}
