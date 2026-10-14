package com.niceday.memo;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.os.UserManager;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import java.util.Calendar;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class ReminderEngineTest {
    Context context;
    ReminderEngine engine;
    long token;
    @Before public void setup() throws Exception {
        context = RuntimeEnvironment.getApplication();
        org.robolectric.shadows.ShadowSystemClock.advanceBy(java.time.Duration.ofDays(21000));
        Shadows.shadowOf(context.getSystemService(UserManager.class)).setUserUnlocked(true);
        Shadows.shadowOf(context.getSystemService(AlarmManager.class)).setCanScheduleExactAlarms(true);
        context.getSharedPreferences("memo", Context.MODE_PRIVATE).edit().clear().commit();
        context.createDeviceProtectedStorageContext().getSharedPreferences("memo-runtime", Context.MODE_PRIVATE).edit().clear().commit();
        Shadows.shadowOf((Application) context).grantPermissions(Manifest.permission.POST_NOTIFICATIONS);
        engine = new ReminderEngine(context);
        token = System.currentTimeMillis() - 1;
        Calendar date = Calendar.getInstance();
        date.add(Calendar.MINUTE, -1);
        JSONObject row = new JSONObject()
            .put("id", 1).put("text", "私人测试内容")
            .put("year", date.get(Calendar.YEAR)).put("month", date.get(Calendar.MONTH) + 1)
            .put("day", date.get(Calendar.DAY_OF_MONTH)).put("hour", date.get(Calendar.HOUR_OF_DAY))
            .put("minute", date.get(Calendar.MINUTE)).put("repeat", "none").put("days", new JSONArray())
            .put("enabled", true).put("sound", false).put("vibration", "off").put("wakeScreen", false)
            .put("intervalMinutes", 1).put("totalCount", 3).put("version", 1)
            .put("nextTrigger", token).put("attempts", 0).put("activeOccurrence", 0);
        persist(row);
    }
    void persist(JSONObject row) {
        context.getSharedPreferences("memo", Context.MODE_PRIVATE).edit()
            .putString("reminders", new JSONArray().put(row).toString()).commit();
    }
    JSONObject row() throws Exception { return new JSONObject(engine.state()).getJSONArray("reminders").getJSONObject(0); }
    Intent intent(String action, long occurrence) {
        return new Intent(action).putExtra("id", 1).putExtra("token", occurrence).putExtra("version", 1L);
    }
    @Test public void noAcknowledgementRetriesOnlyToTotalCount() throws Exception {
        engine.fire(intent(ReminderEngine.BASE, token));
        assertEquals(1, row().getInt("attempts"));
        assertTrue(row().getLong("retryAt") > 0);
        for (int i = 2; i <= 3; i++) {
            JSONObject r = row(); r.put("retryAt", System.currentTimeMillis() - 1); persist(r);
            engine.fire(intent(ReminderEngine.RETRY, token));
            assertEquals(i, row().getInt("attempts"));
        }
        assertEquals(0, row().getLong("retryAt"));
        assertFalse(row().getBoolean("acknowledged"));
        engine.fire(intent(ReminderEngine.RETRY, token));
        assertEquals(3, row().getInt("attempts"));
    }
    @Test public void manualAcknowledgementCancelsRetriesAndNotification() throws Exception {
        engine.fire(intent(ReminderEngine.BASE, token));
        engine.acknowledge(1, token);
        assertTrue(row().getBoolean("acknowledged"));
        assertTrue(row().getBoolean("completed"));
        assertEquals(0, row().getLong("retryAt"));
        engine.fire(intent(ReminderEngine.RETRY, token));
        assertEquals(1, row().getInt("attempts"));
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        assertNull(Shadows.shadowOf(manager).getNotification(1));
    }
    @Test public void staleConfirmationDoesNotAcknowledgeNewOccurrence() throws Exception {
        engine.fire(intent(ReminderEngine.BASE, token));
        engine.acknowledge(1, token - 60000);
        assertFalse(row().getBoolean("acknowledged"));
        assertTrue(row().getLong("retryAt") > 0);
    }
    @Test public void lockedNotificationRedactsActualPayloadAndHasNoFullscreen() throws Exception {
        Shadows.shadowOf(context.getSystemService(KeyguardManager.class)).setKeyguardLocked(true);
        engine.fire(intent(ReminderEngine.BASE, token));
        Notification n = Shadows.shadowOf(context.getSystemService(NotificationManager.class)).getNotification(1);
        assertNotNull(n);
        assertFalse(n.extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("私人"));
        assertNull(n.fullScreenIntent);
        assertEquals(Notification.VISIBILITY_PRIVATE, n.visibility);
        assertNotNull(n.deleteIntent);
        assertEquals(0, n.flags & Notification.FLAG_AUTO_CANCEL);
    }
    @Test public void deletedReminderCannotFireAgain() throws Exception {
        engine.delete(1);
        engine.fire(intent(ReminderEngine.BASE, token));
        assertEquals(0, new JSONObject(engine.state()).getJSONArray("reminders").length());
    }
    JSONObject future(JSONObject r) throws Exception {
        Calendar d = Calendar.getInstance(); d.add(Calendar.MINUTE, 3);
        return r.put("year", d.get(Calendar.YEAR)).put("month", d.get(Calendar.MONTH) + 1)
            .put("day", d.get(Calendar.DAY_OF_MONTH)).put("hour", d.get(Calendar.HOUR_OF_DAY))
            .put("minute", d.get(Calendar.MINUTE));
    }
    @Test public void editingCompletedTaskReactivatesAndRegistersAlarmClock() throws Exception {
        engine.fire(intent(ReminderEngine.BASE, token)); engine.acknowledge(1, token);
        JSONObject r = future(row()); assertFalse(r.getBoolean("enabled"));
        engine.save(r.toString());
        assertTrue(row().getBoolean("enabled")); assertFalse(row().getBoolean("completed"));
        assertTrue(row().getLong("nextTrigger") > System.currentTimeMillis());
        assertNotNull(context.getSystemService(AlarmManager.class).getNextAlarmClock());
    }
    @Test public void legacyInvisibleTaskIsRecovered() throws Exception {
        JSONObject r = future(row()).put("enabled", false).put("completed", false).put("nextTrigger", 0);
        persist(r); engine.restore(false);
        assertTrue(row().getBoolean("enabled")); assertTrue(row().getLong("nextTrigger") > 0);
    }
    @Test public void missingExactPermissionCannotSilentlySaveApproximateTask() throws Exception {
        Shadows.shadowOf(context.getSystemService(AlarmManager.class)).setCanScheduleExactAlarms(false);
        String data = future(row()).toString();
        assertThrows(IllegalArgumentException.class, () -> engine.save(data));
        assertEquals(token, row().getLong("nextTrigger"));
    }
    @Test public void bootRestoreRegistersSystemAlarmWithoutActivity() throws Exception {
        JSONObject r = future(row()).put("nextTrigger", System.currentTimeMillis() + 120000);
        persist(r); engine.restore(false, Intent.ACTION_BOOT_COMPLETED);
        assertNotNull(context.getSystemService(AlarmManager.class).getNextAlarmClock());
        assertTrue(new JSONObject(engine.state()).getJSONObject("status").getLong("lastRestored") > 0);
    }
    @Test public void directBootMetadataContainsNoReminderContentAndMergesAfterUnlock() throws Exception {
        engine.restore(false);
        String metadata = context.createDeviceProtectedStorageContext().getSharedPreferences("memo-runtime", Context.MODE_PRIVATE)
            .getString("reminders", "");
        assertFalse(metadata.contains("私人测试内容")); assertFalse(new JSONArray(metadata).getJSONObject(0).has("text"));
        Shadows.shadowOf(context.getSystemService(UserManager.class)).setUserUnlocked(false);
        ReminderEngine locked = new ReminderEngine(context);
        locked.fire(intent(ReminderEngine.BASE, token)); locked.acknowledge(1, token);
        Shadows.shadowOf(context.getSystemService(UserManager.class)).setUserUnlocked(true);
        JSONObject restored = new JSONObject(new ReminderEngine(context).state()).getJSONArray("reminders").getJSONObject(0);
        assertEquals("私人测试内容", restored.getString("text"));
        assertEquals(1, restored.getInt("attempts")); assertTrue(restored.getBoolean("completed"));
    }
    @Test public void importMergesRemapsIdsAndArchivesPastOneOffs() throws Exception {
        JSONArray records = new JSONArray().put(future(new JSONObject(row().toString()))).put(new JSONObject(row().toString()));
        String backup = new JSONObject().put("format", "timed-memo").put("version", 1).put("reminders", records).toString();
        assertEquals(2, engine.importBackup(backup));
        JSONArray all = new JSONObject(engine.state()).getJSONArray("reminders");
        assertEquals(3, all.length()); assertEquals(1, all.getJSONObject(0).getInt("id"));
        assertNotEquals(1, all.getJSONObject(1).getInt("id"));
        assertTrue(all.getJSONObject(1).getBoolean("enabled")); assertTrue(all.getJSONObject(2).getBoolean("completed"));
    }
    @Test public void invalidImportIsAtomicAndExportRoundTrips() throws Exception {
        assertEquals(1, BackupCodec.decode(engine.exportBackup()).length());
        JSONArray rows = new JSONArray().put(future(new JSONObject(row().toString())))
            .put(new JSONObject(row().toString()).put("day", 32));
        String invalid = new JSONObject().put("format", "timed-memo").put("version", 1).put("reminders", rows).toString();
        assertThrows(IllegalArgumentException.class, () -> engine.importBackup(invalid));
        assertEquals(1, new JSONObject(engine.state()).getJSONArray("reminders").length());
    }
    @Test public void upgradeRestoreReplacesLegacyAlarmBroadcastToken() throws Exception {
        JSONObject r = future(row()).put("nextTrigger", System.currentTimeMillis() + 120000);
        persist(r);
        Intent oldIntent = new Intent(context, ReminderReceiver.class).setAction(ReminderEngine.BASE)
            .setData(android.net.Uri.parse("memo://" + ReminderEngine.BASE + "/1"))
            .putExtra("id", 1).putExtra("token", r.getLong("nextTrigger")).putExtra("version", 1L);
        PendingIntent legacy = PendingIntent.getBroadcast(context, 1, oldIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        engine.restore(false, Intent.ACTION_MY_PACKAGE_REPLACED);
        assertThrows(PendingIntent.CanceledException.class, () -> legacy.send());
        PendingIntent replacement = PendingIntent.getBroadcast(context, 1, oldIntent,
            PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE);
        assertNotNull(replacement);
        // Verify behavior rather than wrapper equality: the replacement must still send.
        replacement.send();
        assertNotNull(context.getSystemService(AlarmManager.class).getNextAlarmClock());
    }
}
