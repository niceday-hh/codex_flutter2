package com.niceday.memo;

import android.app.*;
import android.content.*;
import android.content.pm.PackageInfo;
import android.net.Uri;
import android.os.Build;
import org.json.*;
import java.util.List;

/** Bounded diagnostics without memo text, audio, ringtone URIs, serials or crash descriptions. */
final class ReminderDiagnostics {
    private ReminderDiagnostics() {}
    static JSONArray exits(Context context) throws JSONException {
        JSONArray result = new JSONArray();
        if (Build.VERSION.SDK_INT < 30) return result;
        try {
            List<ApplicationExitInfo> exits = context.getSystemService(ActivityManager.class)
                .getHistoricalProcessExitReasons(context.getPackageName(), 0, 5);
            for (ApplicationExitInfo exit : exits) result.put(new JSONObject().put("at", exit.getTimestamp())
                .put("pid", exit.getPid()).put("reason", exit.getReason()).put("status", exit.getStatus())
                .put("importance", exit.getImportance()));
        } catch (RuntimeException ignored) {}
        return result;
    }
    static boolean tokenExists(Context context, int id, String action) {
        Intent i = new Intent(context, ReminderReceiver.class).setAction(action).setData(Uri.parse("memo://" + action + "/" + id));
        return PendingIntent.getBroadcast(context, id, i, PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE) != null;
    }
    static JSONObject snapshot(Context context, JSONArray reminders) throws JSONException {
        JSONArray rows = new JSONArray();
        for (int i = 0; i < reminders.length(); i++) {
            JSONObject r = reminders.getJSONObject(i), row = new JSONObject();
            for (String field : new String[]{"id", "enabled", "completed", "acknowledged", "repeat", "nextTrigger",
                    "retryAt", "activeOccurrence", "attempts", "totalCount", "lastFired", "lastAck", "version"})
                if (r.has(field)) row.put(field, r.get(field));
            row.put("baseTokenExists", tokenExists(context, r.getInt("id"), ReminderEngine.BASE))
                .put("retryTokenExists", tokenExists(context, r.getInt("id"), ReminderEngine.RETRY));
            rows.put(row);
        }
        JSONObject result = new JSONObject().put("at", System.currentTimeMillis()).put("pid", android.os.Process.myPid())
            .put("manufacturer", Build.MANUFACTURER).put("model", Build.MODEL).put("android", Build.VERSION.RELEASE)
            .put("sdk", Build.VERSION.SDK_INT).put("reminders", rows).put("processExits", exits(context))
            .put("tokenNote", "令牌存在不等于系统排程必定存在；退出原因码也不能单独判断是否强行停止");
        try {
            PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            result.put("version", info.versionName).put("build", Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode);
        } catch (android.content.pm.PackageManager.NameNotFoundException ignored) {}
        return result;
    }
}
