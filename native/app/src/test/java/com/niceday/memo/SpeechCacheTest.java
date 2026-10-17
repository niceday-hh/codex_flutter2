package com.niceday.memo;

import android.content.Context;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import java.io.*;
import java.nio.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class SpeechCacheTest {
    Context c;
    @Before public void setup() {
        c = RuntimeEnvironment.getApplication();
        c.getSharedPreferences("memo", 0).edit().clear().commit();
        File[] files = SpeechCache.directory(c).listFiles();
        if (files != null) for (File f : files) f.delete();
    }
    static void wave(File file) throws Exception {
        ByteBuffer b = ByteBuffer.allocate(100).order(ByteOrder.LITTLE_ENDIAN);
        b.put("RIFF".getBytes()).putInt(92).put("WAVEfmt ".getBytes()).putInt(16).putShort((short)1).putShort((short)1)
            .putInt(22050).putInt(44100).putShort((short)2).putShort((short)16).put("data".getBytes()).putInt(56);
        try (FileOutputStream out = new FileOutputStream(file)) { out.write(b.array()); }
    }
    @Test public void immutableJobsAtomicPromotionAndReuse() throws Exception {
        JSONObject row = new JSONObject().put("id", 1).put("text", "私人内容").put("enabled", true).put("speechMode", "on").put("speechVoice", "33").put("speechRate", 1);
        c.getSharedPreferences("memo", 0).edit().putString("reminders", new JSONArray().put(row).toString()).commit();
        JSONArray jobs = SpeechCache.jobs(c, true);
        assertEquals(2, jobs.length()); assertEquals(SpeechSettings.GENERIC, jobs.getJSONObject(0).getString("text"));
        JSONObject body = jobs.getJSONObject(1);
        assertTrue(body.getString("key").matches("[0-9a-f]{64}\\.wav"));
        assertEquals("preparing", SpeechCache.state(c, row, new JSONObject()));
        wave(new File(body.getString("path"))); SpeechCache.finish(c, body.getString("key"), "");
        assertEquals("ready", SpeechCache.state(c, row, new JSONObject()));
        assertEquals(1, SpeechCache.jobs(c, false).length());
        assertFalse(SpeechCache.file(c, "私人内容", row, new JSONObject()).getPath().contains("私人内容"));
        row.put("text", "新内容"); assertEquals("missing", SpeechCache.state(c, row, new JSONObject()));
    }
    @Test public void rejectsPartialFilesAndUntrustedPaths() throws Exception {
        File f = new File(c.getFilesDir(), "partial.wav");
        try (FileOutputStream out = new FileOutputStream(f)) { out.write(new byte[100]); }
        assertFalse(SpeechCache.ready(f));
        try { SpeechCache.finish(c, "../../other.wav", ""); fail(); } catch (IllegalArgumentException expected) {}
        JSONObject config = new JSONObject().put("speechVoice", "0").put("speechRate", 1);
        JSONObject job = SpeechCache.previewJob(c, config);
        try { SpeechCache.finish(c, job.getString("key"), ""); fail(); } catch (IOException expected) {}
        assertTrue(SpeechCache.status(c).getString("error").length() > 0);
    }
}
