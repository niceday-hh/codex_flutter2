package com.niceday.memo;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.media.*;
import android.net.Uri;
import android.os.*;
import org.json.*;
import java.io.File;
import java.util.ArrayDeque;

/** Only plays prepared audio. Never loads ML models or acknowledges an occurrence. */
public final class SpeechPlaybackService extends Service {
    private static final int NOTIFICATION = 2147483001;
    private static final String CHANNEL = "memo_speech_playback_v1";
    private static SpeechPlaybackService instance;
    private final ArrayDeque<Intent> queue = new ArrayDeque<>();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private MediaPlayer player;
    private AudioFocusRequest focus;
    private PowerManager.WakeLock wake;
    private Intent current;
    private boolean readingBody;
    private boolean registered;
    private int playbackGeneration;
    private final BroadcastReceiver screen = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) {
            if (readingBody && locked() && current != null) {
                try {
                    JSONObject row = new ReminderEngine(c).popupPayload(current.getIntExtra("id", 0), current.getLongExtra("token", 0));
                    if (row == null || SpeechSettings.hideLocked(row, SpeechSettings.defaults(c))) finishCurrent();
                } catch (JSONException e) { finishCurrent(); }
            }
        }
    };
    static void start(Context c, int id, long token) {
        try { c.startForegroundService(new Intent(c, SpeechPlaybackService.class).putExtra("id", id).putExtra("token", token)); }
        catch (RuntimeException e) { new ReminderEngine(c).error("系统限制语音播放，请检查后台运行设置"); }
    }
    static void cancel(int id) {
        SpeechPlaybackService value = instance;
        if (value != null) value.handler.post(() -> {
            value.queue.removeIf(i -> i.getIntExtra("id", 0) == id);
            if (value.current != null && value.current.getIntExtra("id", 0) == id) {
                new ReminderEngine(value).event("speech_stopped", id, value.current.getLongExtra("token", 0), "手动确认或记录变更");
                value.finishCurrent();
            }
        });
    }
    static void pauseForRecording() {
        SpeechPlaybackService value = instance;
        if (value != null) { value.queue.clear(); value.releasePlayer(); value.current = null; value.stopSelf(); }
    }
    private boolean locked() { return getSystemService(KeyguardManager.class).isKeyguardLocked(); }
    @Override public void onCreate() {
        super.onCreate(); instance = this;
        NotificationChannel channel = new NotificationChannel(CHANNEL, "语音播放状态", NotificationManager.IMPORTANCE_LOW);
        channel.setSound(null, null); channel.enableVibration(false);
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
        Notification notification = new Notification.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("定时备忘录").setContentText("正在播放提醒语音")
            .setVisibility(Notification.VISIBILITY_SECRET).setOngoing(true).setSilent(true).build();
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
        else startForeground(NOTIFICATION, notification);
        IntentFilter filter = new IntentFilter(Intent.ACTION_SCREEN_OFF); filter.addAction(Intent.ACTION_USER_PRESENT);
        registerReceiver(screen, filter); registered = true;
    }
    @Override public int onStartCommand(Intent i, int flags, int startId) {
        if (i != null) {
            boolean duplicate = current != null && same(current, i);
            for (Intent pending : queue) duplicate |= same(pending, i);
            if (!duplicate) queue.add(i);
        }
        if (current == null) next();
        return START_NOT_STICKY;
    }
    private static boolean same(Intent a, Intent b) {
        return a.getIntExtra("id", 0) == b.getIntExtra("id", 0) && a.getLongExtra("token", 0) == b.getLongExtra("token", 0);
    }
    private void next() {
        current = queue.poll();
        if (current == null) { stopSelf(); return; }
        try {
            ReminderEngine engine = new ReminderEngine(this);
            JSONObject row = engine.popupPayload(current.getIntExtra("id", 0), current.getLongExtra("token", 0));
            JSONObject defaults = SpeechSettings.defaults(this);
            if (row == null || !SpeechSettings.enabled(row, defaults) || (row.optInt("attempts") > 1 && !row.optBoolean("speechRepeat", true))) {
                finishCurrent(); return;
            }
            readingBody = !(locked() && SpeechSettings.hideLocked(row, defaults));
            File audio = SpeechCache.file(this, readingBody ? row.optString("text") : SpeechSettings.GENERIC, row, defaults);
            AudioAttributes attributes = new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build();
            AudioManager manager = getSystemService(AudioManager.class);
            focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(change -> { if (change < 0) finishCurrent(); }).build();
            if (manager.requestAudioFocus(focus) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { finishCurrent(); return; }
            player = new MediaPlayer(); player.setAudioAttributes(attributes);
            if (SpeechCache.ready(audio)) player.setDataSource(audio.getPath());
            else {
                // No synthesis at the deadline. Respect the configured fallback, including silence.
                if (!row.optBoolean("sound", true)) { finishCurrent(); return; }
                Uri uri = row.optString("ringtone").isEmpty() ? RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) : Uri.parse(row.optString("ringtone"));
                player.setDataSource(this, uri); readingBody = false;
                engine.event("speech_fallback", row.getInt("id"), current.getLongExtra("token", 0), "使用铃声备用提醒");
            }
            player.setOnCompletionListener(p -> finishCurrent());
            player.setOnErrorListener((p, what, extra) -> { finishCurrent(); return true; });
            final int ticket = ++playbackGeneration;
            player.setOnPreparedListener(p -> {
                if (ticket != playbackGeneration || current == null || p != player) return;
                try {
                    // A dismissal or lock may happen during asynchronous preparation.
                    JSONObject fresh = new ReminderEngine(this).popupPayload(current.getIntExtra("id", 0), current.getLongExtra("token", 0));
                    if (fresh == null || (readingBody && locked() && SpeechSettings.hideLocked(fresh, SpeechSettings.defaults(this)))) { finishCurrent(); return; }
                    p.start();
                    new ReminderEngine(this).event("speech_played", fresh.getInt("id"), current.getLongExtra("token", 0), readingBody ? "正文" : "通用提示或备用铃声");
                } catch (Exception e) { finishCurrent(); }
            });
            wake = getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "memo:speech");
            wake.acquire(15 * 60 * 1000L); handler.postDelayed(this::finishCurrent, 15 * 60 * 1000L);
            player.prepareAsync();
        } catch (Exception e) { new ReminderEngine(this).error("语音播放失败，请检查音量及铃声设置"); finishCurrent(); }
    }
    private void releasePlayer() {
        playbackGeneration++;
        handler.removeCallbacksAndMessages(null);
        if (player != null) { player.setOnCompletionListener(null); player.setOnPreparedListener(null); player.setOnErrorListener(null); player.release(); player = null; }
        if (focus != null) { getSystemService(AudioManager.class).abandonAudioFocusRequest(focus); focus = null; }
        if (wake != null && wake.isHeld()) wake.release(); wake = null;
        readingBody = false;
    }
    private void finishCurrent() { releasePlayer(); current = null; next(); }
    @Override public void onDestroy() {
        if (instance == this) instance = null;
        if (registered) unregisterReceiver(screen);
        queue.clear(); current = null; releasePlayer(); stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy();
    }
    @Override public IBinder onBind(Intent i) { return null; }
}
