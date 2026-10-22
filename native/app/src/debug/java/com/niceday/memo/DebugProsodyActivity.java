package com.niceday.memo;

import android.app.Activity;
import android.os.Bundle;
import android.os.SystemClock;
import android.widget.TextView;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import org.json.JSONArray;
import org.json.JSONObject;

/** Isolated foreground model audit; no reminders, Flutter session or production entry point. */
public final class DebugProsodyActivity extends Activity {
    static final String TEXT = "早上七点半，城市刚刚醒来。地铁站里，人们一边看手机，一边快步走向闸机；广播不时提醒：“请站稳扶好，注意脚下安全。”今天的会议安排得有点紧：九点讨论方案，十点半汇报进度，下午两点还要和客户开视频会。小李问：“我们真的能在周五之前完成吗？”老王笑了笑，说：“别急，先把最重要的事做好，剩下的再一件一件处理。”窗外，春雨断断续续地下着，空气里有泥土和青草的味道。2026年4月18日，看起来只是普通的一天，但对团队来说，却可能是最关键的转折点。毕竟，流畅不等于快，自然也不等于随意——该停的时候停，该连的时候连，这才是好的表达。";
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView view = new TextView(this); view.setText("Running offline prosody comparison…"); setContentView(view);
        new Thread(() -> {
            File directory = new File(getFilesDir(), "prosody-audit"); directory.mkdirs();
            File report = new File(directory, "result.json");
            VitsSynthesizer synth = new VitsSynthesizer();
            JSONObject result = new JSONObject(); JSONArray samples = new JSONArray();
            try {
                synth.open(this, TtsAssets.prepare(this));
                render(synth, directory, samples, 5, .8f);
                render(synth, directory, samples, 4, .8f);
                render(synth, directory, samples, 5, .6f);
                result.put("success", true).put("samples", samples).put("speaker", 228)
                    .put("physical_audio_verified", false).put("gender", "female").put("text", TEXT);
            } catch (Throwable error) {
                try { result.put("success", false).put("error", error.toString()).put("samples", samples); } catch (Exception ignored) {}
            } finally {
                synth.close();
                try { Files.write(report.toPath(), result.toString(2).getBytes(StandardCharsets.UTF_8)); } catch (Exception ignored) {}
                runOnUiThread(() -> view.setText(result.toString()));
            }
        }, "prosody-audit").start();
    }
    private static void render(VitsSynthesizer synth, File directory, JSONArray samples, int stage, float rate) throws Exception {
        String name = "stage-" + stage + "-rate-" + Math.round(rate * 10) + ".wav";
        long start = SystemClock.elapsedRealtime();
        File output = new File(directory, name);
        synth.audit = new JSONArray();
        synth.render(TEXT, 228, rate, output, stage);
        samples.put(new JSONObject().put("file", name).put("stage", stage).put("rate", rate)
            .put("punctuation", synth.audit).put("elapsed_ms", SystemClock.elapsedRealtime() - start).put("seconds", (output.length() - 44) / 44100.));
    }
}
