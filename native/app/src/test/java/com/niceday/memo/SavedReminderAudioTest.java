package com.niceday.memo;

import android.content.Context;
import android.net.Uri;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import java.io.*;
import java.nio.file.Files;
import java.util.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class SavedReminderAudioTest {
    Context c;
    final List<JSONObject> held = new ArrayList<>();
    @Before public void setup() throws Exception {
        c = RuntimeEnvironment.getApplication();
        c.getSharedPreferences("memo", 0).edit().clear().commit();
        SpeechCache.jobs(c, true);
    }
    @After public void cleanup() throws Exception {
        for (JSONObject job : held) {
            SpeechCache.releaseAudio(job.getString("lease"));
            if (SpeechCache.pending(job.getString("key"))) SpeechCache.finish(c, job.getString("key"), "cancelled test");
        }
    }
    JSONObject acquire() throws Exception {
        JSONObject job = SpeechCache.reminderAudioJob(c, 7); held.add(job); return job;
    }
    void row() throws Exception {
        c.getSharedPreferences("memo", 0).edit()
            .putString("defaults", new JSONObject().put("speechVoice", "33").put("speechRate", .6).toString())
            .putString("reminders", new JSONArray().put(new JSONObject().put("id", 7).put("text", "这就是保存后的提醒正文")
                .put("speechMode", "off").put("speechVoice", "").put("speechRate", 0).put("enabled", false)).toString()).commit();
    }
    void complete(JSONObject job) throws Exception {
        SpeechCacheTest.wave(new File(job.getString("path")));
        SpeechCache.finish(c, job.getString("key"), "");
    }
    @Test public void savedBodyUsesEffectiveSettingsWithoutEnablingOrChangingTheReminder() throws Exception {
        row(); String before = c.getSharedPreferences("memo", 0).getString("reminders", "");
        JSONObject job = acquire();
        assertEquals("这就是保存后的提醒正文", job.getString("text"));
        assertEquals(33, job.getInt("sid")); assertEquals(.6, job.getDouble("rate"), .0001);
        assertEquals("reminder-7-voice-33.wav", job.getString("filename"));
        assertEquals(before, c.getSharedPreferences("memo", 0).getString("reminders", ""));
        assertFalse(job.getString("filename").contains("正文"));
    }
    @Test public void activeReadersProtectAudioFromPruningUntilEveryLeaseIsReleased() throws Exception {
        row(); JSONObject first = acquire(); complete(first); JSONObject second = acquire();
        assertTrue(second.getBoolean("ready"));
        File file = SpeechCache.leasedAudio(c, first.getString("lease"));
        c.getSharedPreferences("memo", 0).edit().putString("reminders", "[]").commit();
        SpeechCache.prune(c); assertTrue(file.isFile());
        SpeechCache.releaseAudio(first.getString("lease")); SpeechCache.prune(c); assertTrue(file.isFile());
        SpeechCache.releaseAudio(second.getString("lease")); SpeechCache.prune(c); assertFalse(file.exists());
    }
    @Test public void anOpenedSnapshotStillExportsIdenticalWaveBytesAfterCachePruning() throws Exception {
        row(); JSONObject job = acquire(); complete(job);
        File file = SpeechCache.leasedAudio(c, job.getString("lease"));
        byte[] expected = Files.readAllBytes(file.toPath());
        try (InputStream input = new FileInputStream(file); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            c.getSharedPreferences("memo", 0).edit().putString("reminders", "[]").commit();
            SpeechCache.releaseAudio(job.getString("lease")); SpeechCache.prune(c); assertFalse(file.exists());
            assertEquals(expected.length, SavedReminderAudio.copy(input, output));
            assertArrayEquals(expected, output.toByteArray());
        }
    }
    @Test public void unknownRemindersAndLeasesCannotChooseArbitraryPrivateFiles() throws Exception {
        try { SpeechCache.reminderAudioJob(c, 999); fail(); } catch (IllegalArgumentException expected) {}
        try { SpeechCache.leasedAudio(c, "../../shared_prefs/memo.xml"); fail(); } catch (IllegalArgumentException expected) {}
        SpeechCache.releaseAudio("already released");
    }
    @Test public void rejectingANonDocumentDestinationClosesTheSource() throws Exception {
        boolean[] closed = {false};
        InputStream input = new ByteArrayInputStream(new byte[100]) {
            @Override public void close() throws IOException { closed[0] = true; super.close(); }
        };
        try { SavedReminderAudio.write(c, input, Uri.parse("file:///unselected.wav")); fail(); }
        catch (IOException expected) { assertTrue(closed[0]); }
    }
}
