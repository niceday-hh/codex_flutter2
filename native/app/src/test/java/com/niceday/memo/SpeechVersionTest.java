package com.niceday.memo;

import android.content.Context;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import java.io.File;
import java.util.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class SpeechVersionTest {
    Context c; final List<JSONObject> held = new ArrayList<>();
    @Before public void setup() throws Exception {
        c = RuntimeEnvironment.getApplication();
        c.getSharedPreferences("memo", 0).edit().clear().putString("speechModel", "voine-vits-mnn-v1")
            .putString("defaults", new JSONObject().put("speechVoice", "33").put("speechRate", .8)
                .put("speechNoiseScale", .5).put("speechNoiseScaleW", .7).toString())
            .putString("reminders", new JSONArray().put(new JSONObject().put("id", 7).put("text", "今天记得喝水")
                .put("speechMode", "on").put("enabled", true).put("year", 2035).put("month", 1).put("day", 1)
                .put("hour", 12).put("minute", 0).put("activeOccurrence", 1234).put("attempts", 2)).toString()).commit();
        org.robolectric.Shadows.shadowOf(c.getSystemService(android.os.UserManager.class)).setUserUnlocked(true);
        org.robolectric.Shadows.shadowOf(c.getSystemService(android.app.AlarmManager.class)).setCanScheduleExactAlarms(true);
        org.robolectric.Shadows.shadowOf((android.app.Application)c).grantPermissions(android.Manifest.permission.POST_NOTIFICATIONS);
        SpeechSettings.migrateSeeds(c);
    }
    JSONObject row() throws Exception { return new JSONArray(c.getSharedPreferences("memo", 0).getString("reminders", "[]")).getJSONObject(0); }
    JSONObject acquire(boolean candidate) throws Exception {
        JSONObject job = candidate ? SpeechCache.candidateAudioJob(c, 7) : SpeechCache.reminderAudioJob(c, 7); held.add(job); return job;
    }
    void complete(JSONObject job) throws Exception {
        if (job.optJSONArray("companions") != null) for (int i=0;i<job.getJSONArray("companions").length();i++) complete(job.getJSONArray("companions").getJSONObject(i));
        if (!job.getBoolean("ready")) { SpeechCacheTest.wave(new File(job.getString("path"))); SpeechCache.finish(c, job.getString("key"), ""); }
    }
    @After public void cleanup() throws Exception {
        for (JSONObject job : held) {
            SpeechCache.releaseAudio(job.getString("lease"));
            for (JSONObject part : parts(job)) if (SpeechCache.pending(part.getString("key"))) SpeechCache.finish(c, part.getString("key"), "cancelled test");
        }
    }
    List<JSONObject> parts(JSONObject job) throws Exception {
        List<JSONObject> all = new ArrayList<>(); all.add(job);
        JSONArray companions = job.optJSONArray("companions");
        if (companions != null) for (int i=0;i<companions.length();i++) all.add(companions.getJSONObject(i));
        return all;
    }
    @Test public void migrationIsStableAcrossRestartsAndNewTasksGetDifferentSeeds() throws Exception {
        long first = SpeechSettings.seed(row()); assertTrue(first > 0);
        SpeechSettings.migrateSeeds(c); assertEquals(first, SpeechSettings.seed(row()));
        JSONObject selected = acquire(false); complete(selected);
        assertTrue(acquire(false).getBoolean("ready"));
        assertEquals(first, selected.getLong("seed"));
        assertEquals(.5, selected.getDouble("noise"), .00001); assertEquals(.7, selected.getDouble("noiseW"), .00001);
        JSONObject a = SpeechCache.previewJob(c, new JSONObject()), b = SpeechCache.previewJob(c, new JSONObject());
        assertNotEquals(a.getString("key"), b.getString("key"));
        SpeechCache.finish(c, a.getString("key"), "cancelled test"); SpeechCache.finish(c, b.getString("key"), "cancelled test");
    }
    @Test public void aCandidateCannotChangeTheSelectedFileUntilBodyAndPrivacyAudioAreReady() throws Exception {
        JSONObject original = acquire(false); complete(original); String before = row().toString();
        JSONObject candidate = acquire(true); assertNotEquals(original.getString("key"), candidate.getString("key"));
        assertEquals(before, row().toString());
        try { SpeechCache.selectAudio(c, candidate.getString("lease")); fail(); } catch (IllegalStateException expected) {}
        complete(candidate); assertTrue(SpeechCache.audioReady(c, candidate.getString("lease")));
        SpeechCache.selectAudio(c, candidate.getString("lease"));
        JSONObject after = row(); long seed = after.getLong("speechSeed");
        assertEquals(candidate.getLong("seed"), seed);
        after.remove("speechSeed"); JSONObject old = new JSONObject(before); old.remove("speechSeed"); assertEquals(old.toString(), after.toString());
        assertEquals(candidate.getString("key"), acquire(false).getString("key"));
        assertTrue(SpeechCache.ready(SpeechCache.file(c, SpeechSettings.GENERIC, row(), SpeechSettings.defaults(c))));
        SpeechSettings.migrateSeeds(c); assertEquals(seed, SpeechSettings.seed(row()));
    }
    @Test public void discardedCandidatesAndStaleSelectionsLeaveTheCurrentVersionAlone() throws Exception {
        JSONObject original = acquire(false); complete(original);
        JSONObject a = acquire(true), b = acquire(true); complete(a); complete(b);
        assertNotEquals(a.getLong("seed"), b.getLong("seed"));
        SpeechCache.selectAudio(c, a.getString("lease"));
        try { SpeechCache.selectAudio(c, b.getString("lease")); fail(); } catch (IllegalStateException expected) {}
        SpeechCache.releaseAudio(b.getString("lease")); SpeechCache.prune(c);
        assertEquals(a.getString("key"), acquire(false).getString("key"));
    }
    @Test public void timingEditsKeepTheVersionAndSynthesisEditsOrDefaultsReplaceIt() throws Exception {
        ReminderEngine engine = new ReminderEngine(c);
        JSONObject first = row(); long seed = first.getLong("speechSeed");
        engine.save(first.put("hour", 13).toString()); assertEquals(seed, row().getLong("speechSeed"));
        engine.save(row().put("speechNoiseScale", .2).toString()); long changed = row().getLong("speechSeed"); assertNotEquals(seed, changed);
        JSONObject defaults = SpeechSettings.defaults(c); engine.defaults(defaults.put("speechNoiseScale", .9).toString());
        assertEquals(changed, row().getLong("speechSeed")); // Explicit override wins.
        engine.defaults(defaults.put("speechNoiseScaleW", .3).toString()); assertNotEquals(changed, row().getLong("speechSeed"));
    }
}
