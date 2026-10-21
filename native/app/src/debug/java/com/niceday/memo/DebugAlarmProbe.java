package com.niceday.memo;
import android.content.*;
import android.app.*;
import org.json.*;

/** CI-only probe. This receiver is absent from the release APK. */
public final class DebugAlarmProbe extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        try {
            ReminderEngine engine = new ReminderEngine(context);
            if ("PING".equals(intent.getAction())) {
                setResultCode(1); setResultData("probeReady=true");
            } else if ("ENTRY_PREPARE".equals(intent.getAction())) {
                engine.reliableMode(false); engine.defaults(new JSONObject().put("handsFree", false).toString());
            } else if ("ENTRY_SNAPSHOT".equals(intent.getAction())) {
                JSONArray tasks = new JSONArray();
                for (ActivityManager.AppTask task : context.getSystemService(ActivityManager.class).getAppTasks()) {
                    ActivityManager.RecentTaskInfo t = task.getTaskInfo();
                    tasks.put(new JSONObject().put("taskId", t.taskId).put("activities", t.numActivities)
                        .put("base", t.baseActivity == null ? "" : t.baseActivity.getClassName()));
                }
                try (java.io.FileOutputStream out = context.openFileOutput("entry-probe.json", Context.MODE_PRIVATE)) {
                    out.write(tasks.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
                }
            } else if ("VIBRATION_PREVIEW".equals(intent.getAction())) {
                JSONObject requested;
                try { requested = NotificationStyles.preview(context, "once"); }
                catch (IllegalStateException e) {
                    requested = new JSONObject().put("requested", false).put("hardware_absent", e.getMessage().contains("没有可用振动器"));
                }
                try (java.io.FileOutputStream out = context.openFileOutput("vibration-probe.json", Context.MODE_PRIVATE)) {
                    out.write(requested.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
                }
            } else if ("CLEAR".equals(intent.getAction())) {
                JSONArray rows = new JSONObject(engine.state()).getJSONArray("reminders");
                for (int i = 0; i < rows.length(); i++) engine.delete(rows.getJSONObject(i).getInt("id"));
            } else if ("SPEECH_SEED".equals(intent.getAction())) {
                engine.reliableMode(false);
                engine.defaults(new JSONObject().put("sound", false).put("vibration", "off").put("wakeScreen", false)
                    .put("presentation", "drawer").put("speechMode", "on").put("speechVoice", "33").put("speechRate", 1)
                    .put("speechHideLocked", intent.getBooleanExtra("hide", true)).toString());
                int id = engine.createTest(180, 2);
                JSONArray all = new JSONObject(engine.state()).getJSONArray("reminders");
                for (int i = 0; i < all.length(); i++) if (all.getJSONObject(i).getInt("id") == id) {
                    JSONObject row = all.getJSONObject(i).put("text", "请按时完成这条备忘录，记得喝水、整理桌面并准备明天需要的物品。");
                    engine.save(row.toString());
                }
                setResultCode(id);
            } else if ("PREPARE_SPEECH".equals(intent.getAction())) {
                setResultData("preparing=" + MainActivity.requestSpeechPreparation());
            } else if ("SPEECH_STATUS".equals(intent.getAction())) {
                try (java.io.FileOutputStream out = context.openFileOutput("speech-probe.json", Context.MODE_PRIVATE)) {
                    out.write(engine.state().getBytes(java.nio.charset.StandardCharsets.UTF_8));
                }
            } else if ("RETIME_SPEECH".equals(intent.getAction())) {
                JSONArray rows = new JSONObject(engine.state()).getJSONArray("reminders");
                JSONObject row = null;
                for (int i = 0; i < rows.length(); i++) if (rows.getJSONObject(i).getInt("id") == intent.getIntExtra("id", 0)) row = rows.getJSONObject(i);
                if (row == null) throw new IllegalArgumentException("Unknown fixture");
                java.util.Calendar date = java.util.Calendar.getInstance(); date.add(java.util.Calendar.SECOND, 25);
                row.put("year", date.get(java.util.Calendar.YEAR)).put("month", date.get(java.util.Calendar.MONTH) + 1)
                    .put("day", date.get(java.util.Calendar.DAY_OF_MONTH)).put("hour", date.get(java.util.Calendar.HOUR_OF_DAY))
                    .put("minute", date.get(java.util.Calendar.MINUTE)).put("second", date.get(java.util.Calendar.SECOND))
                    .put("millisecond", date.get(java.util.Calendar.MILLISECOND)).put("intervalMinutes", 1).put("totalCount", 2);
                engine.save(row.toString()); setResultCode(row.getInt("id"));
            } else if ("SPEECH_ACK".equals(intent.getAction())) {
                engine.acknowledge(intent.getIntExtra("id", 0), intent.getLongExtra("token", 0));
            } else if ("CLEANUP_DISMISS".equals(intent.getAction()) || "CLEANUP_ACTION".equals(intent.getAction())) {
                int id=intent.getIntExtra("id",0);
                NotificationManager nm=context.getSystemService(NotificationManager.class);
                for (android.service.notification.StatusBarNotification posted:nm.getActiveNotifications()) {
                    if (posted.getId()!=("CLEANUP_DISMISS".equals(intent.getAction())?id:-id)) continue;
                    Notification n=posted.getNotification();
                    if ("CLEANUP_DISMISS".equals(intent.getAction())) { nm.cancel(id); n.deleteIntent.send(); }
                    else n.actions[intent.getIntExtra("index",0)].actionIntent.send();
                    setResultCode(1);
                }
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
                        .put("actionCount", n.actions == null ? 0 : n.actions.length)
                        .put("importance", c.getImportance()).put("sound", c.getSound() == null ? JSONObject.NULL : c.getSound().toString())
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
                int id = "SELF_TEST".equals(intent.getAction()) ? engine.createSelfTest(15)
                    : engine.createTest(intent.getIntExtra("seconds", 15), "BANNER_SEED".equals(intent.getAction()) ? 3 : 1);
                if ("CORE_SEED".equals(intent.getAction())) {
                    if (engine.reliableMode()) throw new IllegalStateException("Core fixture mode did not persist");
                    setResultData("reliableMode=false");
                }
                setResultCode(id);
            }
        } catch (Exception e) { throw new IllegalStateException(e); }
    }
}
