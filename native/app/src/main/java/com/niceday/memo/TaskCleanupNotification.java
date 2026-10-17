package com.niceday.memo;

import android.app.*;
import android.content.*;
import android.net.Uri;
import android.os.Build;
import org.json.*;

/** Low-importance follow-up after a dismissal; never opens a background Activity. */
final class TaskCleanupNotification {
    static void show(Context c,JSONObject row) throws JSONException {
        NotificationManager nm=c.getSystemService(NotificationManager.class);
        NotificationChannel channel=new NotificationChannel("memo_cleanup_v1","任务保留与整理",NotificationManager.IMPORTANCE_LOW);
        channel.setSound(null,null); channel.enableVibration(false); nm.createNotificationChannel(channel);
        int id=row.getInt("id");
        Intent open=new Intent(c,MainActivity.class).setAction("com.niceday.memo.OPEN").setData(Uri.parse("memo://cleanup/"+id))
            .putExtra("reminderId",id).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent content=PendingIntent.getActivity(c,-id,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        boolean recurring=!"none".equals(row.optString("repeat","none"));
        Notification generic=new Notification.Builder(c,"memo_cleanup_v1").setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("提醒已确认").setContentText("解锁后选择保留或删除").setVisibility(Notification.VISIBILITY_PUBLIC).build();
        Notification.Builder b=new Notification.Builder(c,"memo_cleanup_v1").setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("本轮提醒已停止 · 如何保留任务？")
            .setContentText(recurring?"不选择则继续原循环；保留或删除会停止以后的循环":"不选择则保留在历史任务，可随时复用")
            .setContentIntent(content).setVisibility(NotificationStyles.visibility(row)).setPublicVersion(generic)
            .setOnlyAlertOnce(true).setAutoCancel(true).setCategory(Notification.CATEGORY_STATUS);
        for(String action:new String[]{ReminderEngine.ARCHIVE,ReminderEngine.DELETE}) {
            Intent i=new Intent(c,ReminderReceiver.class).setAction(action).setData(Uri.parse("memo://cleanup/"+action+"/"+id))
                .addFlags(Intent.FLAG_RECEIVER_FOREGROUND).putExtra("id",id).putExtra("token",row.optLong("activeOccurrence")).putExtra("version",row.optLong("version"));
            PendingIntent pending=PendingIntent.getBroadcast(c,-id,i,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
            Notification.Action.Builder button=new Notification.Action.Builder(null,ReminderEngine.ARCHIVE.equals(action)?"保留并停用":"删除任务",pending);
            if(Build.VERSION.SDK_INT>=31) button.setAuthenticationRequired(true);
            b.addAction(button.build());
        }
        // Deliberately no deleteIntent: dismissing this optional chooser never loops.
        nm.notify(-id,b.build());
    }
}
