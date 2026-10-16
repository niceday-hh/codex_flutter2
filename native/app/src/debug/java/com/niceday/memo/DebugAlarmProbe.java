package com.niceday.memo;
import android.content.*;
import android.app.*;
import org.json.*;

/** CI-only probe. This receiver is absent from the release APK. */
public final class DebugAlarmProbe extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        try {
            ReminderEngine engine = new ReminderEngine(context);
            if ("CLEAR".equals(intent.getAction())) {
                JSONArray rows = new JSONObject(engine.state()).getJSONArray("reminders");
                for (int i = 0; i < rows.length(); i++) engine.delete(rows.getJSONObject(i).getInt("id"));
            } else if ("KILL_PROCESS".equals(intent.getAction())) {
                // Same-UID shell commands can still be denied by SELinux on emulator images.
                // Finish the ordered broadcast, then send a genuine SIGKILL to this process.
                final int pid = android.os.Process.myPid();
                setResultCode(1); setResultData("killPid=" + pid);
                // A cold Flutter frame can stall the main looper beyond the host's
                // wait. Kill on a separate debug-only thread after the ordered reply.
                new Thread(() -> {
                    android.os.SystemClock.sleep(200);
                    android.os.Process.killProcess(pid);
                }, "ci-process-kill").start();
            } else if ("POPUP_MODE".equals(intent.getAction())) {
                engine.popupMode(intent.getBooleanExtra("enabled", true));
            } else if ("CORE_MODE".equals(intent.getAction())) {
                engine.reliableMode(false);
            } else if ("GUARDIAN_MODE".equals(intent.getAction())) {
                engine.reliableMode(intent.getBooleanExtra("enabled", true));
            } else if ("REMOVE_TASK".equals(intent.getAction())) {
                for (ActivityManager.AppTask task : context.getSystemService(ActivityManager.class).getAppTasks())
                    task.finishAndRemoveTask();
            } else if ("SNAPSHOT".equals(intent.getAction())) {
                JSONArray notifications = new JSONArray();
                NotificationManager manager = context.getSystemService(NotificationManager.class);
                for (android.service.notification.StatusBarNotification posted : manager.getActiveNotifications()) {
                    Notification n = posted.getNotification();
                    NotificationChannel c = manager.getNotificationChannel(n.getChannelId());
                    notifications.put(new JSONObject().put("id", posted.getId()).put("when", n.when)
                        .put("text", String.valueOf(n.extras.getCharSequence(Notification.EXTRA_TEXT)))
                        .put("publicText", n.publicVersion == null ? "" : String.valueOf(n.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT)))
                        .put("visibility", n.visibility).put("fullscreen", n.fullScreenIntent != null)
                        .put("vibrationEnabled", c.shouldVibrate())
                        .put("pattern", c.getVibrationPattern() == null ? JSONObject.NULL : new JSONArray(c.getVibrationPattern())));
                }
                try (java.io.FileOutputStream output = context.openFileOutput("notification-probe.json", Context.MODE_PRIVATE)) {
                    output.write(notifications.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
                }
            } else {
                // Configure and create in one process/ordered call, so a cold-start
                // process transition cannot separate the fixture mode from its task.
                if ("CORE_SEED".equals(intent.getAction())) engine.reliableMode(false);
                if ("PRIVACY_SEED".equals(intent.getAction()) || "BANNER_SEED".equals(intent.getAction())) engine.defaults(new JSONObject()
                    .put("sound", false).put("vibration", "three").put("wakeScreen", false)
                    .put("presentation", "BANNER_SEED".equals(intent.getAction()) ? "banner" : "drawer").put("lockscreen", "private").toString());
                int id = engine.createTest(intent.getIntExtra("seconds", 15), "BANNER_SEED".equals(intent.getAction()) ? 3 : 1);
                if ("CORE_SEED".equals(intent.getAction())) {
                    if (engine.reliableMode()) throw new IllegalStateException("Core fixture mode did not persist");
                    setResultData("reliableMode=false");
                }
                setResultCode(id);
            }
        } catch (Exception e) { throw new IllegalStateException(e); }
    }
}
