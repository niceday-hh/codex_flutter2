package com.niceday.memo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.UserManager;
import android.widget.RemoteViews;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.Calendar;
import java.util.Locale;

/**
 * Home-screen card with the next reminder.
 *
 * It reads the same SharedPreferences the engine writes instead of asking
 * Flutter for state: a widget is drawn by the launcher while our process may be
 * dead, so it must never depend on the Dart isolate. Updates are push-based —
 * {@link ReminderEngine#write} calls {@link #refresh} — because a polling
 * `updatePeriodMillis` would wake the device for nothing.
 */
public final class MemoWidgetProvider extends AppWidgetProvider {
    static final String ACTION_REFRESH = "com.niceday.memo.WIDGET_REFRESH";
    static final String APPEARANCE_PREFS = "memo-appearance";

    @Override public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) update(context, manager, id);
    }

    @Override public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (ACTION_REFRESH.equals(intent.getAction())) refresh(context);
    }

    /** Re-render every placed widget. Safe to call from any write path. */
    static void refresh(Context context) {
        UserManager users = context.getSystemService(UserManager.class);
        // Direct Boot: the credential-encrypted store is unreadable, so there is
        // nothing truthful to show yet.
        if (users != null && !users.isUserUnlocked()) return;
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        if (manager == null) return;
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, MemoWidgetProvider.class));
        if (ids == null || ids.length == 0) return;
        Context app = context.getApplicationContext();
        for (int id : ids) update(app, manager, id);
    }

    private static void update(Context context, AppWidgetManager manager, int widgetId) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.memo_widget);
        JSONObject next = nextRow(context);
        int[] counts = counts(context);
        String time = context.getString(R.string.widget_empty_time);
        String label = context.getString(R.string.widget_label);
        String text = context.getString(R.string.widget_empty_text);
        if (next != null) {
            boolean unread = isUnread(next);
            long at = unread ? next.optLong("activeOccurrence") : next.optLong("nextTrigger");
            time = timeLabel(at);
            text = next.optString("text", "");
            if (text.isEmpty()) text = "有一条提醒待处理";
            if (unread) label = "待确认提醒";
        }
        String count = counts[0] == 0 ? "点按新建第一条"
            : counts[1] > 0 ? counts[1] + " 条待确认 · 共 " + counts[0] + " 条"
            : counts[0] + " 条待处理";

        views.setTextViewText(R.id.widget_label, label);
        views.setTextViewText(R.id.widget_time, time);
        views.setTextViewText(R.id.widget_text, text);
        views.setTextViewText(R.id.widget_count, count);
        views.setInt(R.id.widget_root, "setBackgroundResource", background(context));
        views.setOnClickPendingIntent(R.id.widget_root, open(context));
        manager.updateAppWidget(widgetId, views);
    }

    private static PendingIntent open(Context context) {
        Intent intent = new Intent(context, MainActivity.class)
            .setAction("com.niceday.memo.OPEN")
            .setData(Uri.parse("memo://widget"))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static boolean isUnread(JSONObject r) {
        return r.optLong("activeOccurrence") > 0 && !r.optBoolean("acknowledged");
    }

    /** The unread reminder wins over a future one: it is what the user missed. */
    private static JSONObject nextRow(Context context) {
        try {
            JSONArray rows = new JSONArray(prefs(context).getString("reminders", "[]"));
            JSONObject best = null;
            long bestKey = Long.MAX_VALUE;
            for (int i = 0; i < rows.length(); i++) {
                JSONObject r = rows.getJSONObject(i);
                if (r.optBoolean("archived") || r.optBoolean("completed")) continue;
                boolean unread = isUnread(r);
                long at = unread ? r.optLong("activeOccurrence") : r.optLong("nextTrigger");
                if (at <= 0) continue;
                if (!unread && !r.optBoolean("enabled", true)) continue;
                long key = unread ? 0 : at;
                if (key < bestKey) { bestKey = key; best = r; }
            }
            return best;
        } catch (Exception e) {
            return null;
        }
    }

    /** `[pending, unread]`, counting what the list would show as actionable. */
    private static int[] counts(Context context) {
        int pending = 0, unread = 0;
        try {
            JSONArray rows = new JSONArray(prefs(context).getString("reminders", "[]"));
            for (int i = 0; i < rows.length(); i++) {
                JSONObject r = rows.getJSONObject(i);
                if (r.optBoolean("archived") || r.optBoolean("completed")) continue;
                boolean missed = isUnread(r);
                if (!missed && (!r.optBoolean("enabled", true) || r.optLong("nextTrigger") <= 0)) continue;
                pending++;
                if (missed) unread++;
            }
        } catch (Exception ignored) {}
        return new int[]{pending, unread};
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences("memo", Context.MODE_PRIVATE);
    }

    private static int background(Context context) {
        String accent = context.getSharedPreferences(APPEARANCE_PREFS, Context.MODE_PRIVATE)
            .getString("accent", "violet");
        return switch (accent == null ? "violet" : accent) {
            case "indigo" -> R.drawable.widget_bg_indigo;
            case "teal" -> R.drawable.widget_bg_teal;
            case "ember" -> R.drawable.widget_bg_ember;
            default -> R.drawable.widget_bg_violet;
        };
    }

    private static String timeLabel(long at) {
        Calendar then = Calendar.getInstance();
        then.setTimeInMillis(at);
        String clock = String.format(Locale.CHINA, "%02d:%02d",
            then.get(Calendar.HOUR_OF_DAY), then.get(Calendar.MINUTE));
        Calendar today = Calendar.getInstance();
        if (sameDay(today, then)) return clock;
        today.add(Calendar.DAY_OF_YEAR, 1);
        if (sameDay(today, then)) return "明天 " + clock;
        return (then.get(Calendar.MONTH) + 1) + "月" + then.get(Calendar.DAY_OF_MONTH) + "日 " + clock;
    }

    private static boolean sameDay(Calendar a, Calendar b) {
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR)
            && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR);
    }
}
