package com.niceday.memo;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.content.res.Configuration;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.provider.Settings;
import android.text.TextUtils;
import android.view.*;
import android.widget.*;
import org.json.*;

import java.util.Calendar;
import java.util.Locale;

/** Optional, short-lived unlocked-screen card. Never displays on the keyguard. */
public final class ReminderPopupService extends Service {
    private static final int NOTICE = -2000000002;
    private static final String CHANNEL = "memo_popup_status_v1";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private WindowManager windows;
    private View card;
    private TextView countdown;
    private long lastSecond = -1;
    private int id;
    private long token, deadline;
    private boolean registered;
    private final BroadcastReceiver screenOff = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { stopSelf(); removeCard(); }
    };
    public static boolean mayDisplay(Context c) {
        return Settings.canDrawOverlays(c) && c.getSystemService(PowerManager.class).isInteractive()
            && !c.getSystemService(KeyguardManager.class).isKeyguardLocked()
            && c.getSystemService(UserManager.class).isUserUnlocked();
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        ReminderEngine engine = new ReminderEngine(this);
        try {
            NotificationManager manager = getSystemService(NotificationManager.class);
            NotificationChannel channel = new NotificationChannel(CHANNEL, "亮屏卡片状态", NotificationManager.IMPORTANCE_LOW);
            channel.setSound(null, null); channel.enableVibration(false); channel.setShowBadge(false);
            manager.createNotificationChannel(channel);
            Notification notice = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(com.niceday.memo.R.drawable.ic_notification).setContentTitle("正在显示提醒卡片")
                .setContentText("卡片将在10秒后收起，未读提醒仍保留")
                .setVisibility(Notification.VISIBILITY_SECRET).setOnlyAlertOnce(true).setOngoing(true).build();
            if (Build.VERSION.SDK_INT >= 34) startForeground(NOTICE, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED);
            else if (Build.VERSION.SDK_INT >= 29) startForeground(NOTICE, notice, 0);
            else startForeground(NOTICE, notice);
            if (intent == null || !engine.popupEnabled() || !mayDisplay(this)) { stopSelf(); return START_NOT_STICKY; }
            id = intent.getIntExtra("id", 0); token = intent.getLongExtra("token", 0);
            JSONObject reminder = engine.popupPayload(id, token);
            if (reminder == null) { stopSelf(); return START_NOT_STICKY; }
            removeCard();
            if (!registered) {
                IntentFilter filter = new IntentFilter(Intent.ACTION_SCREEN_OFF);
                if (Build.VERSION.SDK_INT >= 33) registerReceiver(screenOff, filter, Context.RECEIVER_NOT_EXPORTED);
                else registerReceiver(screenOff, filter);
                registered = true;
            }
            windows = getSystemService(WindowManager.class);
            View layout = buildCard(reminder);
            int width = Math.min(getResources().getDisplayMetrics().widthPixels - dp(32), dp(440));
            WindowManager.LayoutParams params = new WindowManager.LayoutParams(width, WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL | WindowManager.LayoutParams.FLAG_SECURE,
                PixelFormat.TRANSLUCENT);
            params.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL; params.y = dp(72); params.setTitle("MemoReminderPopup");
            // Fade instead of the platform's default zoom: an overlay that
            // appears over someone else's app should not feel like a dialog.
            params.windowAnimations = android.R.style.Animation_Toast;
            // Recheck after view construction; never set SHOW_WHEN_LOCKED or turn on the screen here.
            if (!mayDisplay(this)) { stopSelf(); return START_NOT_STICKY; }
            windows.addView(layout, params); card = layout; deadline = SystemClock.elapsedRealtime() + 10000;
            engine.popupError(""); engine.event("popup_shown", id, token, "unlocked;type=2038");
            handler.post(check);
        } catch (Exception e) { engine.popupError("亮屏卡片未显示：" + e.getClass().getSimpleName()); removeCard(); stopSelf(); }
        return START_NOT_STICKY;
    }

    /**
     * A small sheet, not an Android dialog.
     *
     * The old card was a white box with a violet hairline and three platform
     * buttons: grey Material fills, all-caps labels, a shadow under each one,
     * and the same white in both themes. It also ignored the accent the user
     * picked, so a teal app produced a violet card. Everything below is drawn
     * from the same palette as the Flutter side — deep surfaces at night, the
     * brand 500 as the one filled action — with type carrying the hierarchy
     * instead of borders.
     */
    private View buildCard(JSONObject reminder) {
        boolean dark = dark();
        final int surface = dark ? 0xFF191622 : 0xFFFFFFFF;
        final int ink = dark ? 0xFFE9E4F4 : 0xFF25213A;
        final int muted = dark ? 0xFFA79FB9 : 0xFF6B6484;
        final int line = dark ? 0xFF383244 : 0xFFECE8F3;
        final int brandText = brandText(dark);
        final int brandFill = brandFill();

        LinearLayout sheet = new LinearLayout(this);
        sheet.setOrientation(LinearLayout.VERTICAL);
        sheet.setPadding(dp(20), dp(12), dp(20), dp(14));
        sheet.setContentDescription("亮屏提醒卡片");
        GradientDrawable background = new GradientDrawable();
        background.setColor(surface);
        background.setCornerRadius(dp(26));
        background.setStroke(dp(1), line);
        sheet.setBackground(background);
        sheet.setElevation(dp(18));

        // Grab handle. It says "this is a sheet" before a single word is read.
        View handle = new View(this);
        GradientDrawable handleFill = new GradientDrawable();
        handleFill.setColor(line);
        handleFill.setCornerRadius(dp(2));
        handle.setBackground(handleFill);
        LinearLayout.LayoutParams handleParams = new LinearLayout.LayoutParams(dp(36), dp(4));
        handleParams.gravity = Gravity.CENTER_HORIZONTAL;
        handleParams.bottomMargin = dp(14);
        sheet.addView(handle, handleParams);

        LinearLayout head = new LinearLayout(this);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);
        View dot = new View(this);
        GradientDrawable dotFill = new GradientDrawable();
        dotFill.setColor(brandText);
        dotFill.setShape(GradientDrawable.OVAL);
        dot.setBackground(dotFill);
        LinearLayout.LayoutParams dotParams = new LinearLayout.LayoutParams(dp(6), dp(6));
        dotParams.setMarginEnd(dp(7));
        head.addView(dot, dotParams);
        TextView kicker = text("提醒 · 第 " + Math.max(1, reminder.optInt("attempts", 1)) + " 次", 13, brandText);
        kicker.setTypeface(Typeface.DEFAULT_BOLD);
        head.addView(kicker);
        head.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1f));
        // Seeded with the full duration so the first 250ms does not reserve an
        // empty line and then push the clock down when the text appears.
        countdown = text("10 秒后收起", 12, muted);
        head.addView(countdown);
        sheet.addView(head);

        long at = reminder.optLong("activeOccurrence", 0);
        TextView clock = text(clockOf(at, reminder), 26, ink);
        clock.setTypeface(Typeface.DEFAULT_BOLD);
        clock.setLetterSpacing(-0.02f);
        clock.setFontFeatureSettings("'tnum'");
        LinearLayout.LayoutParams clockParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        clockParams.topMargin = dp(12);
        sheet.addView(clock, clockParams);

        TextView body = text(reminder.optString("text", ""), 18, ink);
        body.setTypeface(Typeface.DEFAULT_BOLD);
        body.setMaxLines(3);
        body.setEllipsize(TextUtils.TruncateAt.END);
        body.setLineSpacing(dp(2), 1f);
        LinearLayout.LayoutParams bodyParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        bodyParams.topMargin = dp(5);
        sheet.addView(body, bodyParams);

        String meta = metaOf(at, reminder);
        if (!meta.isEmpty()) {
            TextView metaView = text(meta, 12, muted);
            LinearLayout.LayoutParams metaParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            metaParams.topMargin = dp(8);
            sheet.addView(metaView, metaParams);
        }

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams actionsParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        actionsParams.topMargin = dp(16);
        sheet.addView(actions, actionsParams);

        TextView read = button("已读", brandFill, 0xFFFFFFFF, 0);
        read.setOnClickListener(v -> acknowledge());
        actions.addView(read, new LinearLayout.LayoutParams(0, dp(46), 1f));

        TextView dismiss = button("收起", 0x00000000, muted, line);
        // Regular weight: the filled button is the decision, this is the way
        // out. Two bold labels would read as two equal choices again.
        dismiss.setTypeface(Typeface.DEFAULT);
        dismiss.setOnClickListener(v -> { removeCard(); stopSelf(); });
        LinearLayout.LayoutParams dismissParams = new LinearLayout.LayoutParams(dp(88), dp(46));
        dismissParams.setMarginStart(dp(10));
        actions.addView(dismiss, dismissParams);

        TextView hint = text("右滑已读 · 上滑收起", 12, muted);
        hint.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams hintParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        hintParams.topMargin = dp(10);
        sheet.addView(hint, hintParams);

        sheet.setOnTouchListener(new View.OnTouchListener() {
            float downX, downY;
            @Override public boolean onTouch(View v, android.view.MotionEvent event) {
                if (event.getAction() == MotionEvent.ACTION_DOWN) { downX = event.getRawX(); downY = event.getRawY(); return true; }
                if (event.getAction() == MotionEvent.ACTION_UP) {
                    float dx = event.getRawX() - downX, dy = event.getRawY() - downY;
                    // Right and up only, and only when the drag is clearly
                    // horizontal or vertical. The old rule acknowledged on any
                    // 80dp sideways movement, so a stray left swipe marked a
                    // reminder read — the one action that should be deliberate.
                    if (dx > dp(96) && Math.abs(dx) > Math.abs(dy) * 1.5f) acknowledge();
                    else if (dy < -dp(72) && Math.abs(dy) > Math.abs(dx) * 1.5f) { removeCard(); stopSelf(); }
                    else v.performClick();
                    return true;
                }
                return true;
            }
        });
        return sheet;
    }

    private final Runnable check = new Runnable() {
        @Override public void run() {
            try {
                ReminderEngine engine = new ReminderEngine(ReminderPopupService.this);
                if (card == null || SystemClock.elapsedRealtime() >= deadline || !mayDisplay(ReminderPopupService.this)
                    || !engine.popupEnabled() || engine.popupPayload(id, token) == null) { removeCard(); stopSelf(); return; }
                long left = Math.max(0, (deadline - SystemClock.elapsedRealtime() + 999) / 1000);
                if (countdown != null && left != lastSecond) {
                    lastSecond = left;
                    countdown.setText(left + " 秒后收起");
                }
                handler.postDelayed(this, 250);
            } catch (Exception e) { removeCard(); stopSelf(); }
        }
    };
    private void acknowledge() {
        try { new ReminderEngine(this).acknowledge(id, token); }
        catch (Exception e) { new ReminderEngine(this).popupError("确认已读失败，请在通知栏重试"); }
        removeCard(); stopSelf();
    }

    private boolean dark() {
        SharedPreferences prefs = getSharedPreferences(MemoWidgetProvider.APPEARANCE_PREFS, MODE_PRIVATE);
        String mode = prefs.getString("mode", "system");
        if ("dark".equals(mode)) return true;
        if ("light".equals(mode)) return false;
        int ui = getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
        return ui == Configuration.UI_MODE_NIGHT_YES;
    }
    private String accent() {
        String value = getSharedPreferences(MemoWidgetProvider.APPEARANCE_PREFS, MODE_PRIVATE)
            .getString("accent", "violet");
        return value == null ? "violet" : value;
    }
    /** The filled action always carries white text, so it always takes the
     *  light ramp's 500 — the dark ramp's pastel 500 would leave white at 3:1. */
    private int brandFill() {
        return switch (accent()) {
            case "indigo" -> 0xFF4468E8;
            case "teal" -> 0xFF1A8168;
            case "ember" -> 0xFFB25C12;
            default -> 0xFF7252F6;
        };
    }
    /** Labels sit on the card, not on the fill, so they take whichever end of
     *  the ramp reads against that surface. */
    private int brandText(boolean dark) {
        if (dark) return switch (accent()) {
            case "indigo" -> 0xFF7D93FF;
            case "teal" -> 0xFF4FBFA5;
            case "ember" -> 0xFFD98A45;
            default -> 0xFF8C74FF;
        };
        return switch (accent()) {
            case "indigo" -> 0xFF3253CC;
            case "teal" -> 0xFF146D59;
            case "ember" -> 0xFF9E4F0F;
            default -> 0xFF5B3FD9;
        };
    }
    private String clockOf(long at, JSONObject reminder) {
        Calendar then = Calendar.getInstance();
        if (at > 0) then.setTimeInMillis(at);
        else { then.set(Calendar.HOUR_OF_DAY, reminder.optInt("hour")); then.set(Calendar.MINUTE, reminder.optInt("minute")); }
        return String.format(Locale.CHINA, "%02d:%02d", then.get(Calendar.HOUR_OF_DAY), then.get(Calendar.MINUTE));
    }
    private String metaOf(long at, JSONObject reminder) {
        StringBuilder meta = new StringBuilder(dayLabel(at));
        String repeat = repeatLabel(reminder);
        if (!repeat.isEmpty()) { if (meta.length() > 0) meta.append(" · "); meta.append(repeat); }
        return meta.toString();
    }
    private String dayLabel(long at) {
        if (at <= 0) return "";
        Calendar then = Calendar.getInstance(); then.setTimeInMillis(at);
        Calendar today = Calendar.getInstance();
        if (sameDay(today, then)) return "今天";
        today.add(Calendar.DAY_OF_YEAR, 1);
        if (sameDay(today, then)) return "明天";
        return (then.get(Calendar.MONTH) + 1) + "月" + then.get(Calendar.DAY_OF_MONTH) + "日";
    }
    private String repeatLabel(JSONObject reminder) {
        String repeat = reminder.optString("repeat", "none");
        if ("daily".equals(repeat)) return "每天";
        if (!"weekly".equals(repeat)) return "";
        JSONArray days = reminder.optJSONArray("days");
        if (days == null || days.length() == 0) return "每周";
        String[] names = {"一", "二", "三", "四", "五", "六", "日"};
        StringBuilder label = new StringBuilder("每周");
        for (int i = 0; i < days.length(); i++) {
            int day = days.optInt(i);
            if (day < 1 || day > 7) continue;
            if (i > 0) label.append("、");
            label.append(names[day - 1]);
        }
        return label.toString();
    }
    private static boolean sameDay(Calendar a, Calendar b) {
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR)
            && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR);
    }
    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setIncludeFontPadding(false);
        return view;
    }
    private TextView button(String label, int fill, int ink, int stroke) {
        TextView view = text(label, 15, ink);
        view.setTypeface(Typeface.DEFAULT_BOLD);
        view.setGravity(Gravity.CENTER);
        GradientDrawable background = new GradientDrawable();
        background.setColor(fill);
        background.setCornerRadius(dp(14));
        if (stroke != 0) background.setStroke(dp(1), stroke);
        view.setBackground(background);
        view.setClickable(true);
        view.setFocusable(true);
        return view;
    }
    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density + 0.5f); }
    private void removeCard() {
        handler.removeCallbacks(check);
        if (card != null) { try { windows.removeViewImmediate(card); } catch (RuntimeException ignored) {} card = null; }
        countdown = null; lastSecond = -1;
    }
    @Override public void onDestroy() {
        removeCard(); if (registered) unregisterReceiver(screenOff);
        stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
