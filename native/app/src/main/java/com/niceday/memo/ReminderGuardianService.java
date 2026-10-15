package com.niceday.memo;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.os.*;
import org.json.*;

/** Visible, opt-out alarm maintenance. Never bypasses force-stop or uses polling/wakelocks. */
public final class ReminderGuardianService extends Service {
    public static final int NOTIFICATION_ID = -2000000001;
    private static final String CHANNEL = "memo_guardian_v1";
    private boolean restored;
    private static volatile boolean active;

    @Override public void onCreate() {
        super.onCreate();
        new ReminderEngine(this).captureSnapshot("serviceLaunchSnapshot");
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        ReminderEngine engine = new ReminderEngine(this);
        try {
            // Promote before storage/restore work so the foreground start deadline is met.
            NotificationManager manager = getSystemService(NotificationManager.class);
            NotificationChannel channel = new NotificationChannel(CHANNEL, "可靠提醒状态", NotificationManager.IMPORTANCE_LOW);
            channel.setSound(null, null); channel.enableVibration(false); channel.setShowBadge(false);
            manager.createNotificationChannel(channel);
            Intent open = new Intent(this, MainActivity.class).setAction("com.niceday.memo.RELIABILITY")
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            PendingIntent content = PendingIntent.getActivity(this, NOTIFICATION_ID, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            Notification notice = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(com.niceday.memo.R.drawable.ic_notification).setContentTitle("可靠提醒已开启")
                .setContentText("正在维护定时提醒，可在应用设置中关闭")
                .setContentIntent(content).setCategory(Notification.CATEGORY_SERVICE)
                .setVisibility(Notification.VISIBILITY_PRIVATE).setOngoing(true).setOnlyAlertOnce(true).build();
            if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION_ID, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED);
            else if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notice, 0);
            else startForeground(NOTIFICATION_ID, notice);
            if (!engine.reliableMode() || engine.pendingSummary().getInt("count") == 0) {
                active = false; stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY;
            }
            active = true;
            if (!restored || intent == null) {
                restored = true;
                engine.event("guardian_started", 0, 0, intent == null ? "系统恢复服务" : "启动可靠提醒");
                engine.restoreFromService();
            }
            engine.guardianError("");
            return START_STICKY;
        } catch (Exception e) {
            engine.guardianError("可靠提醒未能运行：" + e.getClass().getSimpleName());
            active = false; stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY;
        }
    }
    @Override public void onTaskRemoved(Intent rootIntent) {
        ReminderEngine engine = new ReminderEngine(this);
        engine.event("task_removed", 0, 0, "最近任务被移除");
        try { if (engine.reliableMode()) engine.restoreFromService(); }
        catch (Exception e) { engine.guardianError("移除任务后恢复失败：" + e.getClass().getSimpleName()); }
        super.onTaskRemoved(rootIntent);
    }
    @Override public void onDestroy() {
        active = false;
        new ReminderEngine(this).event("guardian_stopped", 0, 0, "可靠服务停止");
        stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
    // All components use the default application process. This flag is reset by process death.
    static boolean running(Context context) { return active; }
}
