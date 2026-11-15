package com.niceday.memo;

import android.content.Context;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import java.io.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class RetryAnnouncementTest {
    JSONObject row() throws Exception {
        return new JSONObject().put("id", 81).put("text", "关火").put("enabled", true).put("speechMode", "on")
            .put("speechAnnounceRetry", true).put("speechRepeat", true).put("totalCount", 5).put("intervalMinutes", 3)
            .put("speechVoice", "228").put("speechRate", .8).put("speechSeed", 555);
    }
    @Test public void firstIsUnchangedLaterCountsUseActualIntervalAndReset() throws Exception {
        JSONObject row = row();
        assertEquals("", SpeechSettings.retryAnnouncement(row, 1));
        assertEquals("当前为第二次提醒，提醒间隔三分钟。", SpeechSettings.retryAnnouncement(row, 2));
        assertEquals("当前为第五次提醒，提醒间隔三分钟。", SpeechSettings.retryAnnouncement(row, 5));
        assertEquals("", SpeechSettings.retryAnnouncement(row, 6));
        assertEquals("", SpeechSettings.retryAnnouncement(row, 1)); // Next daily occurrence.
        row.put("intervalMinutes", 120).put("totalCount", 20);
        assertEquals("当前为第二十次提醒，提醒间隔一百二十分钟。", SpeechSettings.retryAnnouncement(row, 20));
        row.put("speechRepeat", false); assertEquals("", SpeechSettings.retryAnnouncement(row, 2));
        row.put("speechRepeat", true).put("speechAnnounceRetry", false); assertEquals("", SpeechSettings.retryAnnouncement(row, 2));
        assertEquals("", SpeechSettings.retryAnnouncement(new JSONObject(), 2));
    }
    @Test public void suffixesArePreparedReusedPrunedAndDoNotReplaceBody() throws Exception {
        Context c = RuntimeEnvironment.getApplication(); JSONObject row = row();
        c.getSharedPreferences("memo", 0).edit().clear().putString("reminders", new JSONArray().put(row).toString()).commit();
        File[] old = SpeechCache.directory(c).listFiles(); if (old != null) for (File f : old) f.delete();
        JSONArray jobs = SpeechCache.jobs(c, true); assertEquals(6, jobs.length());
        assertEquals("关火", jobs.getJSONObject(1).getString("text"));
        for (int i = 0; i < jobs.length(); i++) {
            JSONObject job = jobs.getJSONObject(i);
            assertEquals(555, job.getInt("seed")); assertEquals(.8, job.getDouble("rate"), .0001); assertEquals(228, job.getInt("sid"));
            SpeechCacheTest.wave(new File(job.getString("path"))); SpeechCache.finish(c, job.getString("key"), "");
        }
        assertEquals("ready", SpeechCache.state(c, row, new JSONObject())); assertEquals(0, SpeechCache.jobs(c, false).length());
        String bodyKey = SpeechCache.file(c, "关火", row, new JSONObject()).getName();
        String oldSuffix = SpeechCache.file(c, SpeechSettings.retryAnnouncement(row, 2), row, new JSONObject()).getName();
        row.put("intervalMinutes", 10);
        c.getSharedPreferences("memo", 0).edit().putString("reminders", new JSONArray().put(row).toString()).commit();
        assertEquals(bodyKey, SpeechCache.file(c, "关火", row, new JSONObject()).getName());
        assertEquals("missing", SpeechCache.state(c, row, new JSONObject()));
        assertEquals(4, SpeechCache.jobs(c, false).length()); assertFalse(new File(SpeechCache.directory(c), oldSuffix).exists());
    }
    @Test public void settingIsValidatedAndSurvivesBackup() throws Exception {
        JSONObject row = row(); SpeechSettings.validate(row, false); assertTrue(row.getBoolean("speechAnnounceRetry"));
        try { SpeechSettings.validate(new JSONObject().put("speechAnnounceRetry", "true"), false); fail(); }
        catch (IllegalArgumentException expected) {}
        assertTrue(new JSONObject(row.toString()).getBoolean("speechAnnounceRetry"));
    }
}
