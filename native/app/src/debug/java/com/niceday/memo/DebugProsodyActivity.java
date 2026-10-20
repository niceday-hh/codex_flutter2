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
    static final String TEXT = "关于这个超级提醒APP，目前还有几点需要优化：\n首先第一点就是每次从其他地方进入到界面里都会切到首页并开始录音，这个是可以的，但是在进入界面之后切换到不同tab页，再切回主页tab，它还是会重新开始录音这一部分，其实可以省略的，防止它反复的开始录音、停止录音，造成不必要的开销。其实可以只保留从外部软件或者是桌面切换到该APP时才重新开始准备预听语音指令。";
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
                for (int stage = 0; stage <= 3; stage++) render(synth, directory, samples, stage, .8f);
                render(synth, directory, samples, 3, .6f);
                render(synth, directory, samples, 3, .5f);
                result.put("success", true).put("samples", samples).put("speaker", 228)
                    .put("physical_audio_verified", false).put("text", TEXT);
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
        synth.render(TEXT, 228, rate, output, stage);
        samples.put(new JSONObject().put("file", name).put("stage", stage).put("rate", rate)
            .put("elapsed_ms", SystemClock.elapsedRealtime() - start).put("seconds", (output.length() - 44) / 44100.));
    }
}
