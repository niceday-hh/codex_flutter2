package com.niceday.memo;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;
import org.json.*;

/** Optional, short-lived unlocked-screen card. Never displays on the keyguard. */
public final class ReminderPopupService extends Service {
    private static final int NOTICE = -2000000002;
    private static final String CHANNEL = "memo_popup_status_v1";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private WindowManager windows;
    private View card;
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
            LinearLayout layout = new LinearLayout(this);
            layout.setOrientation(LinearLayout.VERTICAL); layout.setPadding(dp(20), dp(16), dp(20), dp(10));
            layout.setContentDescription("亮屏提醒卡片"); layout.setElevation(dp(14));
            GradientDrawable background = new GradientDrawable(); background.setColor(Color.WHITE); background.setCornerRadius(dp(22));
            background.setStroke(dp(1), 0xFFE5DEFF); layout.setBackground(background);
            TextView title = label("超级提醒 · 第" + reminder.optInt("attempts") + "次", 13, 0xFF7252F6);
            layout.addView(title);
            TextView body = label(reminder.getString("text"), 20, 0xFF252039); body.setMaxLines(4);
            body.setEllipsize(android.text.TextUtils.TruncateAt.END); body.setPadding(0, dp(10), 0, dp(10));
            body.setTypeface(null, Typeface.BOLD); layout.addView(body);
            LinearLayout actions = new LinearLayout(this); actions.setGravity(Gravity.END);
            Button hide = new Button(this); hide.setText("收起"); hide.setOnClickListener(v -> { removeCard(); stopSelf(); }); actions.addView(hide);
            Button read = new Button(this); read.setText("已读"); read.setTextColor(0xFF7252F6); read.setOnClickListener(v -> acknowledge()); actions.addView(read);
            layout.addView(actions); layout.addView(label("自动收起不会标为已读 · 横向滑动确认已读", 11, 0xFF777184));
            layout.setOnTouchListener(new View.OnTouchListener() {
                float down;
                @Override public boolean onTouch(View v, android.view.MotionEvent event) {
                    if (event.getAction() == MotionEvent.ACTION_DOWN) { down = event.getRawX(); return true; }
                    if (event.getAction() == MotionEvent.ACTION_UP) {
                        if (Math.abs(event.getRawX() - down) > dp(80)) acknowledge();
                        else v.performClick();
                        return true;
                    }
                    return true;
                }
            });
            int width = Math.min(getResources().getDisplayMetrics().widthPixels - dp(32), dp(440));
            WindowManager.LayoutParams params = new WindowManager.LayoutParams(width, WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL | WindowManager.LayoutParams.FLAG_SECURE,
                PixelFormat.TRANSLUCENT);
            params.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL; params.y = dp(72); params.setTitle("MemoReminderPopup");
            // Recheck after view construction; never set SHOW_WHEN_LOCKED or turn on the screen here.
            if (!mayDisplay(this)) { stopSelf(); return START_NOT_STICKY; }
            windows.addView(layout, params); card = layout; deadline = SystemClock.elapsedRealtime() + 10000;
            engine.popupError(""); engine.event("popup_shown", id, token, "unlocked;type=2038");
            handler.post(check);
        } catch (Exception e) { engine.popupError("亮屏卡片未显示：" + e.getClass().getSimpleName()); removeCard(); stopSelf(); }
        return START_NOT_STICKY;
    }
    private final Runnable check = new Runnable() {
        @Override public void run() {
            try {
                ReminderEngine engine = new ReminderEngine(ReminderPopupService.this);
                if (card == null || SystemClock.elapsedRealtime() >= deadline || !mayDisplay(ReminderPopupService.this)
                    || !engine.popupEnabled() || engine.popupPayload(id, token) == null) { removeCard(); stopSelf(); return; }
                handler.postDelayed(this, 250);
            } catch (Exception e) { removeCard(); stopSelf(); }
        }
    };
    private void acknowledge() {
        try { new ReminderEngine(this).acknowledge(id, token); }
        catch (Exception e) { new ReminderEngine(this).popupError("确认已读失败，请在通知栏重试"); }
        removeCard(); stopSelf();
    }
    private TextView label(String value, int size, int color) {
        TextView text = new TextView(this); text.setText(value); text.setTextSize(size); text.setTextColor(color); return text;
    }
    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density + 0.5f); }
    private void removeCard() {
        handler.removeCallbacks(check);
        if (card != null) { try { windows.removeViewImmediate(card); } catch (RuntimeException ignored) {} card = null; }
    }
    @Override public void onDestroy() {
        removeCard(); if (registered) unregisterReceiver(screenOff);
        stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
