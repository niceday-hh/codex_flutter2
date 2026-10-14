package com.niceday.memo;

import android.Manifest;
import android.app.*;
import android.content.*;
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
        context.getSharedPreferences("memo", Context.MODE_PRIVATE).edit().clear().commit();
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
}
