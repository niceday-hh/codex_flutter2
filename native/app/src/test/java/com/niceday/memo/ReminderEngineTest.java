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
    @Test public void notificationDismissalStopsRetriesAndOffersSilentArchiveChoice() throws Exception {
        Shadows.shadowOf(context.getSystemService(KeyguardManager.class)).setKeyguardLocked(false);
        engine.fire(intent(ReminderEngine.BASE,token)); engine.dismissed(1,token);
        assertTrue(row().getBoolean("acknowledged")); assertTrue(row().getBoolean("completed")); assertEquals(0,row().getLong("retryAt"));
        NotificationManager nm=context.getSystemService(NotificationManager.class);
        Notification prompt=Shadows.shadowOf(nm).getNotification(-1);
        assertNotNull(prompt); assertEquals(2,prompt.actions.length); assertNull(prompt.deleteIntent);
        assertNull(nm.getNotificationChannel(prompt.getChannelId()).getSound());
        assertFalse(prompt.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("私人"));
        Intent action=Shadows.shadowOf(prompt.actions[0].actionIntent).getSavedIntent();
        engine.cleanupAction(action);
        assertTrue(row().getBoolean("archived")); assertFalse(row().getBoolean("enabled"));
        assertEquals("私人测试内容",row().getString("text")); assertEquals(0,row().getLong("nextTrigger"));
        assertNull(Shadows.shadowOf(nm).getNotification(-1));
    }
    @Test public void staleCleanupCannotDeleteEditedTaskAndPromptCanBeDisabled() throws Exception {
        Shadows.shadowOf(context.getSystemService(KeyguardManager.class)).setKeyguardLocked(false);
        engine.fire(intent(ReminderEngine.BASE,token)); engine.dismissed(1,token);
        Notification prompt=Shadows.shadowOf(context.getSystemService(NotificationManager.class)).getNotification(-1);
        Intent action=Shadows.shadowOf(prompt.actions[1].actionIntent).getSavedIntent();
        engine.save(future(row()).toString()); engine.cleanupAction(action);
        assertEquals(1,new JSONObject(engine.state()).getJSONArray("reminders").length()); assertFalse(row().optBoolean("archived"));
        engine.cleanupPrompts(false);
        JSONObject r=row().put("nextTrigger",token); persist(r);
        Intent fire=intent(ReminderEngine.BASE,token).putExtra("version",r.getLong("version")); engine.fire(fire); engine.dismissed(1,token);
        assertNull(Shadows.shadowOf(context.getSystemService(NotificationManager.class)).getNotification(-1));
    }
    @Test public void recurringDismissalKeepsFutureOccurrencesUntilExplicitArchive() throws Exception {
        JSONObject r=row().put("repeat","daily");persist(r);
        engine.fire(intent(ReminderEngine.BASE,token)); long next=row().getLong("nextTrigger");
        engine.dismissed(1,token);
        assertTrue(row().getBoolean("enabled")); assertFalse(row().optBoolean("completed")); assertEquals(next,row().getLong("nextTrigger"));
        engine.archive(1); assertEquals(0,row().getLong("nextTrigger")); assertFalse(row().getBoolean("enabled"));
    }
    @Test public void archiveSurvivesBackupAndEditingExplicitlyReactivatesIt() throws Exception {
        engine.save(future(row()).toString()); engine.archive(1);
        JSONObject portable=BackupCodec.decode(engine.exportBackup()).getJSONObject(0);
        assertTrue(portable.getBoolean("archived"));
        engine.importBackup(engine.exportBackup()); JSONArray rows=new JSONObject(engine.state()).getJSONArray("reminders");
        assertEquals(2,rows.length()); assertTrue(rows.getJSONObject(1).getBoolean("archived")); assertFalse(rows.getJSONObject(1).getBoolean("enabled"));
        engine.save(future(row()).toString());
        rows=new JSONObject(engine.state()).getJSONArray("reminders"); JSONObject edited=rows.getJSONObject(1);
        assertEquals(1,edited.getInt("id")); assertFalse(edited.getBoolean("archived")); assertFalse(edited.getBoolean("completed")); assertTrue(edited.getBoolean("enabled"));
    }
    @Test public void aishellUpgradeResetsOnlyVoiceAndPreservesExistingSchedule() throws Exception {
        java.io.File legacy=new java.io.File(context.getFilesDir(),"tts-aishell3-v1"); legacy.mkdirs();
        java.nio.file.Files.write(new java.io.File(legacy,"model.onnx").toPath(),new byte[]{1,2});
        JSONObject r=row().put("speechVoice","33").put("speechMode","on"); persist(r);
        context.getSharedPreferences("memo",0).edit().remove("speechModel").commit();
        engine=new ReminderEngine(context);
        assertEquals("228",row().getString("speechVoice")); assertEquals("on",row().getString("speechMode")); assertEquals(token,row().getLong("nextTrigger"));
        assertFalse(legacy.exists());
    }
    @Test public void speechNotificationDoesNotRingAndBackupFreezesInheritedVoice() throws Exception {
        engine.defaults(new JSONObject().put("speechMode", "on").put("speechVoice", "33").put("speechRate", 0.9).toString());
        JSONObject r = future(row()).put("speechMode", "inherit").put("speechHideLocked", false).put("sound", true);
        engine.save(r.toString());
        JSONObject saved = row();
        NotificationChannel channel = context.getSystemService(NotificationManager.class).getNotificationChannel(saved.getString("notificationChannelId"));
        assertNull(channel.getSound());
        JSONObject portable = BackupCodec.decode(engine.exportBackup()).getJSONObject(0);
        assertEquals("on", portable.getString("speechMode")); assertEquals("33", portable.getString("speechVoice"));
        assertEquals(0.9, portable.getDouble("speechRate"), 0.001); assertFalse(portable.getBoolean("speechHideLocked"));
        assertFalse(engine.exportBackup().contains("speech-audio"));
    }
    @Test public void preciseDateSurvivesSaveMirrorRestoreAndBackup() throws Exception {
        JSONObject r = future(row()).put("second", 43).put("millisecond", 625);
        engine.save(r.toString());
        long planned = row().getLong("nextTrigger");
        Calendar c = Calendar.getInstance(); c.setTimeInMillis(planned);
        assertEquals(43, c.get(Calendar.SECOND)); assertEquals(625, c.get(Calendar.MILLISECOND));
        engine.restore(false); assertEquals(planned, row().getLong("nextTrigger"));
        JSONArray mirror = new JSONArray(context.createDeviceProtectedStorageContext().getSharedPreferences("memo-runtime", Context.MODE_PRIVATE).getString("reminders", "[]"));
        assertEquals(43, mirror.getJSONObject(0).getInt("second"));
        assertEquals(625, mirror.getJSONObject(0).getInt("millisecond"));
        JSONArray decoded = BackupCodec.decode(engine.exportBackup());
        assertEquals(43, decoded.getJSONObject(0).getInt("second"));
        assertEquals(625, decoded.getJSONObject(0).getInt("millisecond"));
        r.put("second", 60);
        try { BackupCodec.validateReminder(r); fail("invalid seconds accepted"); } catch (IllegalArgumentException expected) {}
    }
    @Test public void popupDefaultsOffAndOnlyCurrentUnreadOccurrenceSuppliesBody() throws Exception {
        assertFalse(engine.popupEnabled()); engine.popupMode(true); assertTrue(engine.popupEnabled());
        assertNull(engine.popupPayload(1, token));
        engine.fire(intent(ReminderEngine.BASE, token));
        assertNotNull(engine.popupPayload(1, token)); assertNull(engine.popupPayload(1, token - 1));
        engine.acknowledge(1, token); assertNull(engine.popupPayload(1, token));
        engine.popupMode(false); assertFalse(engine.popupEnabled());
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
    @Test public void notificationCarriesPrivateBodyAndSafeLockscreenVersionWithoutFullscreen() throws Exception {
        Shadows.shadowOf(context.getSystemService(KeyguardManager.class)).setKeyguardLocked(true);
        engine.fire(intent(ReminderEngine.BASE, token));
        Notification n = Shadows.shadowOf(context.getSystemService(NotificationManager.class)).getNotification(1);
        assertNotNull(n);
        assertEquals("私人测试内容", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
        assertNotNull(n.publicVersion);
        assertFalse(n.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("私人"));
        assertNull(n.publicVersion.extras.getCharSequence(Notification.EXTRA_BIG_TEXT));
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
    @Test public void drawerHiddenReminderUsesNormalPriorityAndProtectsLockedPayload() throws Exception {
        JSONObject r = row().put("presentation", "drawer").put("lockscreen", "hidden"); persist(r);
        Shadows.shadowOf(context.getSystemService(KeyguardManager.class)).setKeyguardLocked(true);
        engine.fire(intent(ReminderEngine.BASE, token));
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        Notification n = Shadows.shadowOf(manager).getNotification(1);
        assertEquals(Notification.VISIBILITY_SECRET, n.visibility);
        assertNull(n.fullScreenIntent);
        assertFalse(n.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("私人"));
        assertEquals(NotificationManager.IMPORTANCE_DEFAULT, manager.getNotificationChannel(n.getChannelId()).getImportance());
        assertEquals("", new JSONObject(engine.state()).getJSONObject("status").getString("lastError"));
    }
    @Test public void referencedStylesAreGroupedAndUnusedHistoryIsRetainedButHidden() throws Exception {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel("memo_v2_history", "历史样式", NotificationManager.IMPORTANCE_LOW));
        JSONArray rows = new JSONArray(); JSONObject template = row();
        for (int id = 1; id <= 10; id++) rows.put(new JSONObject(template.toString()).put("id", id)
            .put("ringtone", "content://different-unused-ringtone/" + id));
        context.getSharedPreferences("memo", Context.MODE_PRIVATE).edit().putString("reminders", rows.toString()).commit();
        engine.defaults(new JSONObject().put("sound", false).put("vibration", "off").toString());
        JSONObject status = new JSONObject(engine.state()).getJSONObject("status");
        JSONArray groups = status.getJSONArray("notificationStyles");
        assertEquals(1, groups.length()); assertEquals(10, groups.getJSONObject(0).getInt("count"));
        assertTrue(groups.getJSONObject(0).getBoolean("isDefault"));
        assertTrue(status.getInt("hiddenChannelCount") >= 1);
        assertNotNull(manager.getNotificationChannel("memo_v2_history"));
    }
    @Test public void upgradingReusesLegacyChannelAndPreservesSystemChoices() throws Exception {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        String legacy = "memo_v2_" + Integer.toHexString(("false:off:" + android.media.RingtoneManager
            .getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)).hashCode());
        NotificationChannel channel = new NotificationChannel(legacy, "旧名称", NotificationManager.IMPORTANCE_LOW);
        channel.enableVibration(false); channel.setSound(null, null);
        manager.createNotificationChannel(channel);
        engine.restore(false, Intent.ACTION_MY_PACKAGE_REPLACED);
        engine.fire(intent(ReminderEngine.BASE, token));
        Notification n = Shadows.shadowOf(manager).getNotification(1);
        assertEquals(legacy, n.getChannelId());
        assertEquals(NotificationManager.IMPORTANCE_LOW, manager.getNotificationChannel(legacy).getImportance());
        assertFalse(manager.getNotificationChannel(legacy).shouldVibrate());
        assertTrue(new JSONObject(engine.state()).getJSONObject("status").getJSONArray("notificationStyles")
            .getJSONObject(0).getBoolean("systemOverridden"));
    }
    @Test public void directBootKeepsCustomSoundChannelWithoutLeakingItsUri() throws Exception {
        JSONObject r = row().put("sound", true).put("ringtone", "content://private/ringtone/71")
            .put("presentation", "drawer").put("lockscreen", "hidden"); persist(r);
        engine.restore(false);
        String expected = row().getString("notificationChannelId");
        String mirror = context.createDeviceProtectedStorageContext().getSharedPreferences("memo-runtime", Context.MODE_PRIVATE)
            .getString("reminders", "");
        assertFalse(mirror.contains("content://private")); assertFalse(mirror.contains("私人测试内容"));
        Shadows.shadowOf(context.getSystemService(UserManager.class)).setUserUnlocked(false);
        new ReminderEngine(context).fire(intent(ReminderEngine.BASE, token));
        Notification n = Shadows.shadowOf(context.getSystemService(NotificationManager.class)).getNotification(1);
        assertEquals(expected, n.getChannelId()); assertEquals(Notification.VISIBILITY_SECRET, n.visibility);
    }
    @Test public void selfTestFollowsCurrentDefaultsButOnlyAlertsOnce() throws Exception {
        engine.defaults(new JSONObject().put("presentation", "drawer").put("lockscreen", "hidden")
            .put("vibration", "twice").put("sound", false).put("wakeScreen", false).toString());
        int id = engine.createTest(15);
        JSONArray rows = new JSONObject(engine.state()).getJSONArray("reminders");
        JSONObject test = rows.getJSONObject(rows.length() - 1);
        assertEquals(id, test.getInt("id")); assertEquals("drawer", test.getString("presentation"));
        assertEquals("hidden", test.getString("lockscreen")); assertEquals("twice", test.getString("vibration"));
        assertFalse(test.getBoolean("sound")); assertFalse(test.getBoolean("wakeScreen"));
        assertEquals(1, test.getInt("totalCount"));
    }
    @Test public void styleShortcutDoesNotSaveOrRescheduleReminder() throws Exception {
        long trigger = row().getLong("nextTrigger");
        String id = engine.channelForStyle(new JSONObject().put("presentation", "drawer").put("lockscreen", "hidden").toString());
        assertNotNull(context.getSystemService(NotificationManager.class).getNotificationChannel(id));
        assertEquals(trigger, row().getLong("nextTrigger"));
        assertEquals(1, new JSONObject(engine.state()).getJSONArray("reminders").length());
        assertNull(context.getSystemService(AlarmManager.class).getNextAlarmClock());
    }
    @Test public void oldBackupUsesPrivateBannerDefaultsAndNewFieldsRoundTripPortably() throws Exception {
        JSONObject legacy = new JSONObject(row().toString()); legacy.remove("presentation"); legacy.remove("lockscreen");
        JSONArray old = BackupCodec.decode(new JSONObject().put("format", "timed-memo").put("version", 1)
            .put("reminders", new JSONArray().put(legacy)).toString());
        assertEquals("banner", old.getJSONObject(0).getString("presentation"));
        assertEquals("private", old.getJSONObject(0).getString("lockscreen"));
        persist(future(row()).put("presentation", "drawer").put("lockscreen", "hidden")); engine.restore(false);
        String backup = engine.exportBackup();
        assertFalse(backup.contains("notificationChannelId")); assertFalse(backup.contains("notificationStyle"));
        engine.importBackup(backup);
        JSONArray rows = new JSONObject(engine.state()).getJSONArray("reminders");
        assertEquals("drawer", rows.getJSONObject(1).getString("presentation"));
        assertEquals("hidden", rows.getJSONObject(1).getString("lockscreen"));
    }
    @Test public void invalidDisplayImportDoesNotPartiallyImportEarlierValidRows() throws Exception {
        JSONArray rows = new JSONArray().put(future(new JSONObject(row().toString())))
            .put(new JSONObject(row().toString()).put("lockscreen", "public"));
        String invalid = new JSONObject().put("format", "timed-memo").put("version", 1).put("reminders", rows).toString();
        assertThrows(IllegalArgumentException.class, () -> engine.importBackup(invalid));
        assertEquals(1, new JSONObject(engine.state()).getJSONArray("reminders").length());
    }
    @Test public void firstCredentialUnlockRefreshesDirectBootPlaceholderWithoutAnotherAttempt() throws Exception {
        engine.restore(false);
        Shadows.shadowOf(context.getSystemService(UserManager.class)).setUserUnlocked(false);
        new ReminderEngine(context).fire(intent(ReminderEngine.BASE, token));
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        Notification masked = Shadows.shadowOf(manager).getNotification(1);
        assertFalse(masked.extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("私人"));
        Shadows.shadowOf(context.getSystemService(UserManager.class)).setUserUnlocked(true);
        ReminderEngine afterUnlock = new ReminderEngine(context);
        afterUnlock.refreshNotifications();
        Notification full = Shadows.shadowOf(manager).getNotification(1);
        JSONObject r = new JSONObject(afterUnlock.state()).getJSONArray("reminders").getJSONObject(0);
        assertEquals("私人测试内容", full.extras.getCharSequence(Notification.EXTRA_TEXT).toString());
        assertTrue((full.flags & Notification.FLAG_ONLY_ALERT_ONCE) != 0);
        assertEquals(masked.when, full.when);
        assertEquals(1, r.getInt("attempts")); assertEquals(token, r.getLong("activeOccurrence"));
        assertFalse(r.getBoolean("acknowledged")); assertTrue(r.getLong("retryAt") > 0);
    }
    @Test public void refreshingNotificationsCannotResurrectDismissedOrAcknowledgedMessages() throws Exception {
        engine.fire(intent(ReminderEngine.BASE, token));
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        manager.cancel(1); engine.refreshNotifications();
        assertNull(Shadows.shadowOf(manager).getNotification(1));
        engine.acknowledge(1, token); engine.refreshNotifications();
        assertNull(Shadows.shadowOf(manager).getNotification(1));
    }
    @Test public void changedSystemVibrationIsReportedAndNotSilentlyOverwritten() throws Exception {
        JSONObject r = row().put("vibration", "three"); persist(r);
        String legacy = "memo_v2_" + Integer.toHexString(("false:three:" + android.media.RingtoneManager
            .getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)).hashCode());
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(legacy, "用户调整的节奏", NotificationManager.IMPORTANCE_HIGH);
        channel.setVibrationPattern(new long[]{0, 250}); channel.setSound(null, null);
        manager.createNotificationChannel(channel);
        JSONObject group = new JSONObject(engine.state()).getJSONObject("status").getJSONArray("notificationStyles").getJSONObject(0);
        assertTrue(group.getBoolean("vibrationMismatch")); assertTrue(group.getBoolean("systemOverridden"));
        assertTrue(group.getString("actualVibration").contains("1 段"));
        assertArrayEquals(new long[]{0, 250}, manager.getNotificationChannel(legacy).getVibrationPattern());
    }

    @Test public void reliableModeCanBeDisabledWithoutCancellingNativeAlarm() throws Exception {
        engine.save(future(row()).toString());
        AlarmManager manager = context.getSystemService(AlarmManager.class);
        assertNotNull(manager.getNextAlarmClock());
        engine.reliableMode(false);
        assertFalse(engine.reliableMode());
        assertNotNull(manager.getNextAlarmClock());
        assertTrue(ReminderDiagnostics.tokenExists(context, 1, ReminderEngine.BASE));
    }
    @Test public void pendingSummaryCountsRetryButExcludesAcknowledgedAndInactiveRows() throws Exception {
        long now = System.currentTimeMillis();
        JSONArray rows = new JSONArray()
            .put(new JSONObject(row().toString()).put("id", 1).put("nextTrigger", now + 300000))
            .put(new JSONObject(row().toString()).put("id", 2).put("nextTrigger", 0).put("retryAt", now + 60000))
            .put(new JSONObject(row().toString()).put("id", 3).put("enabled", false))
            .put(new JSONObject(row().toString()).put("id", 4).put("nextTrigger", 0).put("retryAt", now + 1).put("acknowledged", true))
            .put(new JSONObject(row().toString()).put("id", 5).put("nextTrigger", 0).put("retryAt", 0));
        context.getSharedPreferences("memo", Context.MODE_PRIVATE).edit().putString("reminders", rows.toString()).commit();
        assertEquals(2, engine.pendingSummary().getInt("count"));
        assertEquals(now + 60000, engine.pendingSummary().getLong("earliest"));
    }
    @Test public void visibleStickyServiceRestoresTaskRemovalWithoutConsumingAttempt() throws Exception {
        persist(future(row()).put("nextTrigger", System.currentTimeMillis() + 120000));
        org.robolectric.android.controller.ServiceController<ReminderGuardianService> controller =
            Robolectric.buildService(ReminderGuardianService.class).create();
        ReminderGuardianService service = controller.get();
        try {
            assertEquals(Service.START_STICKY, service.onStartCommand(null, 0, 1));
            assertTrue(ReminderGuardianService.running(context));
            Notification n = Shadows.shadowOf(service).getLastForegroundNotification();
            assertNotNull(n); assertNotEquals(0, n.flags & Notification.FLAG_ONGOING_EVENT);
            assertFalse(n.extras.toString().contains("私人测试内容"));
            NotificationChannel channel = context.getSystemService(NotificationManager.class).getNotificationChannel(n.getChannelId());
            assertNull(channel.getSound()); assertFalse(channel.shouldVibrate());
            service.onTaskRemoved(new Intent());
            assertNotNull(context.getSystemService(AlarmManager.class).getNextAlarmClock());
            assertEquals(0, row().getInt("attempts"));
            assertFalse(row().optBoolean("acknowledged"));
            assertTrue(new JSONObject(engine.state()).getJSONObject("status").getJSONArray("trace").toString().contains("task_removed"));
        } finally { controller.destroy(); }
        assertFalse(ReminderGuardianService.running(context));
    }
    @Test public void serviceDoesNotStayForegroundWithNoPendingWork() throws Exception {
        persist(row().put("nextTrigger", 0).put("retryAt", 0));
        org.robolectric.android.controller.ServiceController<ReminderGuardianService> controller =
            Robolectric.buildService(ReminderGuardianService.class).create();
        try {
            assertEquals(Service.START_NOT_STICKY, controller.get().onStartCommand(null, 0, 1));
            assertTrue(Shadows.shadowOf(controller.get()).isStoppedBySelf());
            assertFalse(ReminderGuardianService.running(context));
        } finally { controller.destroy(); }
    }
    @Test public void diagnosticsRetainBeforeRestoreSnapshotAndExcludePrivateContent() throws Exception {
        persist(future(row()).put("nextTrigger", System.currentTimeMillis() + 120000)
            .put("ringtone", "content://private/secret-song").put("audio", "private-recording"));
        engine.captureSnapshot("launchSnapshot");
        engine.restore(false);
        String exported = engine.exportDiagnostics();
        assertFalse(exported.contains("私人测试内容")); assertFalse(exported.contains("secret-song"));
        assertFalse(exported.contains("private-recording")); assertFalse(exported.contains("notificationStyles"));
        JSONObject report = new JSONObject(exported);
        assertEquals("timed-memo-diagnostics", report.getString("format"));
        assertFalse(report.getJSONObject("launchBeforeRestore").getJSONArray("reminders").getJSONObject(0).getBoolean("baseTokenExists"));
        assertTrue(report.getJSONObject("current").getJSONArray("reminders").getJSONObject(0).getBoolean("baseTokenExists"));
        assertEquals(0, row().getInt("attempts"));
    }
    @Test public void staleAlarmGenerationIsDiagnosedWithoutConsumingAttempt() throws Exception {
        engine.fire(intent(ReminderEngine.BASE, token).putExtra("version", 999L));
        assertEquals(0, row().getInt("attempts"));
        assertTrue(new JSONObject(engine.state()).getJSONObject("status").getJSONArray("trace").toString().contains("rejected"));
    }
}
