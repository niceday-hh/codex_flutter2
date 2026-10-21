package com.niceday.memo;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import org.json.*;

/** CI-only real-model checks. Absent from the installable release APK. */
public final class DebugSamplingActivity extends Activity {
    static final String TEXT = "早上七点半，城市刚刚醒来。地铁站里，人们一边看手机，一边快步走向闸机；广播不时提醒：“请站稳扶好，注意脚下安全。”今天的会议安排得有点紧";
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView view = new TextView(this); view.setText("Checking offline sampling and selected audio…"); setContentView(view);
        int id = getIntent().getIntExtra("id", 0);
        new Thread(() -> {
            JSONObject report = new JSONObject(); VitsSynthesizer synth = new VitsSynthesizer();
            JSONObject original = null, candidate = null, discarded = null;
            File directory = new File(getFilesDir(), "sampling-audit"); directory.mkdirs();
            try {
                original = SpeechCache.reminderAudioJob(this, id);
                String before = rawRow(id).toString();
                synth.open(this, TtsAssets.prepare(this));
                candidate = SpeechCache.candidateAudioJob(this, id); generate(synth, candidate);
                if (!rawRow(id).toString().equals(before)) throw new IllegalStateException("Candidate changed selected reminder");
                SpeechCache.selectAudio(this, candidate.getString("lease"));
                JSONObject after = rawRow(id), previous = new JSONObject(before);
                long selectedSeed = after.getLong("speechSeed"); after.remove("speechSeed"); previous.remove("speechSeed");
                if (!after.toString().equals(previous.toString())) throw new IllegalStateException("Selection changed reminder scheduling/state");
                File selected = SpeechCache.file(this, rawRow(id).getString("text"), rawRow(id), SpeechSettings.defaults(this));
                String selectedHash = hash(selected);
                if (!selected.getName().equals(candidate.getString("key"))) throw new IllegalStateException("Playback uses another cache key");
                discarded = SpeechCache.candidateAudioJob(this, id); generate(synth, discarded);
                if (discarded.getLong("seed") == selectedSeed) throw new IllegalStateException("Candidate seed reused");
                SpeechCache.releaseAudio(discarded.getString("lease")); SpeechCache.prune(this);
                new ReminderEngine(this);
                if (rawRow(id).getLong("speechSeed") != selectedSeed || !hash(selected).equals(selectedHash))
                    throw new IllegalStateException("Discard/reload replaced selected audio");
                report.put("candidate_preserved_current_until_selected", true).put("selection_only_changed_seed", true)
                    .put("discard_and_reload_keep_selected", true).put("selected_cache_sha256", selectedHash)
                    .put("selected_seed", selectedSeed).put("selected_noise", candidate.getDouble("noise"))
                    .put("selected_noise_w", candidate.getDouble("noiseW"));
                String a = render(synth, directory, "base", TEXT, .6f, .668f, 101);
                int shortCount = synth.lastSegmentCount;
                String repeat = render(synth, directory, "repeat", TEXT, .6f, .668f, 101);
                String random = render(synth, directory, "random", TEXT, .6f, .668f, 202);
                String noise = render(synth, directory, "noise", TEXT, .2f, .668f, 101);
                String timing = render(synth, directory, "timing", TEXT, .6f, .2f, 101);
                render(synth, directory, "long", TEXT.repeat(4), .6f, .668f, 101);
                if (shortCount != 1 || synth.lastSegmentCount < 2) throw new IllegalStateException("Whole short text/long splitting failed");
                if (!a.equals(repeat) || a.equals(random) || a.equals(noise) || a.equals(timing)) throw new IllegalStateException("Sampling parameters/seed not effective");
                report.put("same_seed_reproduces", true).put("new_seed_changes_audio", true)
                    .put("noise_scale_effective", true).put("noise_scale_w_effective", true)
                    .put("short_68_char_segments", shortCount).put("long_text_segments", synth.lastSegmentCount)
                    .put("physical_audio_verified", false).put("success", true);
            } catch (Throwable e) {
                try { report.put("success", false).put("error", e.toString()); } catch (JSONException ignored) {}
            } finally {
                synth.close();
                try {
                    if (original != null) SpeechCache.releaseAudio(original.getString("lease"));
                    if (candidate != null) SpeechCache.releaseAudio(candidate.getString("lease"));
                    if (discarded != null) SpeechCache.releaseAudio(discarded.getString("lease"));
                    Files.write(new File(directory, "result.json").toPath(), report.toString(2).getBytes(StandardCharsets.UTF_8));
                } catch (Exception ignored) {}
                runOnUiThread(() -> view.setText(report.toString()));
            }
        }, "sampling-audit").start();
    }
    private JSONObject rawRow(int id) throws Exception {
        JSONArray rows = new JSONArray(getSharedPreferences("memo", 0).getString("reminders", "[]"));
        for (int i=0;i<rows.length();i++) if (rows.getJSONObject(i).getInt("id") == id) return rows.getJSONObject(i);
        throw new IllegalArgumentException("Unknown reminder");
    }
    private void generate(VitsSynthesizer synth, JSONObject job) throws Exception {
        JSONArray companions = job.optJSONArray("companions");
        if (companions != null) for (int i=0;i<companions.length();i++) generate(synth, companions.getJSONObject(i));
        if (!job.getBoolean("ready")) { synth.generate(this, job); SpeechCache.finish(this, job.getString("key"), ""); }
    }
    private static String render(VitsSynthesizer synth, File directory, String name, String text, float noise, float noiseW, long seed) throws Exception {
        File output = new File(directory, name + ".wav");
        synth.render(text, 228, .8f, output, 4, noise, noiseW, seed);
        return hash(output);
    }
    private static String hash(File file) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(file.toPath()));
        StringBuilder text = new StringBuilder(); for (byte b : digest) text.append(String.format("%02x", b & 255)); return text.toString();
    }
}
