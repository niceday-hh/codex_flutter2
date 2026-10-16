package com.niceday.memo;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.KeyguardManager;
import org.json.JSONObject;
import android.content.*;
import android.content.pm.PackageManager;
import android.media.*;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.view.WindowManager;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.io.*;

public final class MainActivity extends FlutterActivity {
    private static boolean capturedLaunch;
    private static java.lang.ref.WeakReference<MainActivity> foreground = new java.lang.ref.WeakReference<>(null);
    private AlertDialog reminderDialog;
    private boolean resumed;
    static boolean showReminder(JSONObject reminder, long token) {
        MainActivity activity = foreground.get();
        if (activity == null || !activity.resumed || activity.isFinishing()
            || activity.getSystemService(KeyguardManager.class).isKeyguardLocked()
            || !activity.getSystemService(PowerManager.class).isInteractive()) return false;
        activity.runOnUiThread(() -> {
            if (!activity.resumed || activity.getSystemService(KeyguardManager.class).isKeyguardLocked()) return;
            if (activity.reminderDialog != null) activity.reminderDialog.dismiss();
            AlertDialog dialog = new AlertDialog.Builder(activity).setTitle("定时备忘录")
                .setMessage(reminder.optString("text"))
                .setNegativeButton("收起", null).setPositiveButton("已读", (d, which) -> {
                    try { new ReminderEngine(activity).acknowledge(reminder.optInt("id"), token); }
                    catch (Exception e) { new ReminderEngine(activity).error("确认已读失败，请在通知栏重试"); }
                }).create();
            activity.reminderDialog = dialog; dialog.show();
            dialog.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
            new Handler(Looper.getMainLooper()).postDelayed(dialog::dismiss, 10000);
        });
        return true;
    }
    static boolean isRecordingAudio() {
        MainActivity activity = foreground.get();
        return activity != null && activity.recording;
    }
    static boolean requestSpeechPreparation() {
        MainActivity activity = foreground.get();
        if (activity == null || !activity.resumed || activity.channel == null) return false;
        activity.channel.invokeMethod("prepareSpeech", null); return true;
    }
    private MethodChannel channel;
    private SharedPreferences memoPreferences;
    private SharedPreferences.OnSharedPreferenceChangeListener memoListener;
    private MethodChannel.Result permissionResult, ringtoneResult;
    private MethodChannel.Result documentResult;
    private String exportDocument;
    private final java.util.concurrent.ExecutorService documents = java.util.concurrent.Executors.newSingleThreadExecutor();
    private MediaPlayer speechPreview;
    private AudioRecord recorder;
    private Thread audioThread;
    private volatile boolean recording;
    private volatile String audioError;
    private File audioFile;

    @Override public void onCreate(Bundle state) {
        if (!capturedLaunch) { new ReminderEngine(this).captureSnapshot("launchSnapshot"); capturedLaunch = true; }
        super.onCreate(state);
        // Prevent reminder text leaking through task-switcher previews or screenshots.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
    }
    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "memo/native");
        memoPreferences = getSharedPreferences("memo", Context.MODE_PRIVATE);
        memoListener = (preferences, key) -> {
            if (("reminders".equals(key) || "speechChanged".equals(key)) && channel != null) channel.invokeMethod("stateChanged", null);
        };
        memoPreferences.registerOnSharedPreferenceChangeListener(memoListener);
        channel.setMethodCallHandler((call, result) -> {
            try {
                ReminderEngine store = new ReminderEngine(this);
                switch (call.method) {
                    case "getState" -> result.success(store.state());
                    case "prepareAsr" -> documents.execute(() -> {
                        try { String path = AsrAssets.prepare(getApplicationContext()); runOnUiThread(() -> result.success(path)); }
                        catch (Exception e) { runOnUiThread(() -> result.error("ASR", "模型准备失败：" + e.getMessage(), null)); }
                    });
                    case "prepareTts" -> documents.execute(() -> {
                        try { String path = TtsAssets.prepare(getApplicationContext()); runOnUiThread(() -> result.success(path)); }
                        catch (Exception e) { runOnUiThread(() -> result.error("TTS", "播报模型准备失败", null)); }
                    });
                    case "speechJobs" -> result.success(SpeechCache.jobs(this, Boolean.TRUE.equals(call.arguments)).toString());
                    case "speechFinished" -> {
                        String key = call.argument("key"), failure = call.argument("error");
                        SpeechCache.finish(this, key, failure == null ? "" : failure); result.success(null);
                    }
                    case "speechPreviewJob" -> {
                        JSONObject config = new JSONObject((String) call.arguments);
                        SpeechSettings.validate(config, false);
                        result.success(SpeechCache.previewJob(this, config).toString());
                    }
                    case "playSpeechPreview" -> {
                        stopSpeechPreview();
                        String key = (String)call.arguments;
                        if (!key.matches("[0-9a-f]{64}\\.wav") || !resumed || getSystemService(KeyguardManager.class).isKeyguardLocked())
                            throw new IllegalStateException("请解锁并保持试听页面打开");
                        File audio = new File(SpeechCache.directory(this), key);
                        if (!SpeechCache.ready(audio)) throw new IllegalStateException("试听语音尚未准备");
                        speechPreview = new MediaPlayer();
                        speechPreview.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build());
                        speechPreview.setDataSource(audio.getPath());
                        speechPreview.setOnCompletionListener(p -> stopSpeechPreview());
                        speechPreview.setOnErrorListener((p, a, b) -> { stopSpeechPreview(); return true; });
                        speechPreview.setOnPreparedListener(MediaPlayer::start); speechPreview.prepareAsync(); result.success(null);
                    }
                    case "stopSpeechPreview" -> { stopSpeechPreview(); result.success(null); }
                    case "filesDir" -> result.success(getFilesDir().getAbsolutePath());
                    case "save" -> { store.save((String) call.arguments); result.success(null); }
                    case "saveDefaults" -> { store.defaults((String) call.arguments); result.success(null); }
                    case "delete" -> { store.delete((Integer) call.arguments); result.success(null); }
                    case "ack" -> {
                        Number id = call.argument("id"), token = call.argument("token");
                        store.acknowledge(id.intValue(), token.longValue()); result.success(null);
                    }
                    case "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (permissionResult != null) throw new IllegalStateException("权限请求处理中");
                            permissionResult = result;
                            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 101);
                        } else result.success(true);
                    }
                    case "requestExact" -> {
                        if (Build.VERSION.SDK_INT >= 31) startActivity(new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:" + getPackageName())));
                        result.success(null);
                    }
                    case "notificationSettings" -> {
                        startActivity(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName()));
                        result.success(null);
                    }
                    case "batterySettings" -> {
                        startActivity(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)); result.success(null);
                    }
                    case "appSettings" -> {
                        startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:" + getPackageName()))); result.success(null);
                    }
                    case "pickRingtone" -> {
                        if (ringtoneResult != null) throw new IllegalStateException("铃声选择处理中");
                        Intent picker = new Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_NOTIFICATION)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "选择提醒铃声");
                        String uri = (String) call.arguments;
                        picker.putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                            uri == null || uri.isEmpty() ? RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) : Uri.parse(uri));
                        ringtoneResult = result;
                        startActivityForResult(picker, 103);
                    }
                    case "startRecording" -> {
                        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            if (permissionResult != null) throw new IllegalStateException("权限请求处理中");
                            permissionResult = result;
                            requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 102);
                        } else { startRecording(); result.success(null); }
                    }
                    case "stopRecording" -> result.success(stopRecording(false));
                    case "cancelRecording" -> { stopRecording(true); result.success(null); }
                    case "initialReminderId" -> result.success(getIntent().getIntExtra("reminderId", 0));
                    case "restore" -> { store.restore(false); result.success(null); }
                    case "testReminder" -> result.success(store.createTest(15));
                    case "popupMode" -> {
                        boolean enabled = (Boolean) call.arguments;
                        store.popupMode(enabled);
                        if (enabled && !Settings.canDrawOverlays(this)) startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + getPackageName())));
                        result.success(null);
                    }
                    case "reliableMode" -> { store.reliableMode((Boolean) call.arguments); result.success(null); }
                    case "previewVibration" -> { NotificationStyles.preview(this, (String) call.arguments); result.success(null); }
                    case "notificationStyleSettings" -> {
                        String id = store.channelForStyle((String) call.arguments);
                        startActivity(new Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName()).putExtra(Settings.EXTRA_CHANNEL_ID, id));
                        result.success(null);
                    }
                    case "channelSettings" -> {
                        String id = (String) call.arguments;
                        startActivity(new Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName()).putExtra(Settings.EXTRA_CHANNEL_ID, id));
                        result.success(null);
                    }
                    case "exportBackup" -> {
                        if (documentResult != null) throw new IllegalStateException("文件操作处理中");
                        exportDocument = store.exportBackup(); documentResult = result;
                        startActivityForResult(new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/json")
                            .addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE, "timed-memo-backup.json"), 104);
                    }
                    case "exportDiagnostics" -> {
                        if (documentResult != null) throw new IllegalStateException("文件操作处理中");
                        exportDocument = store.exportDiagnostics(); documentResult = result;
                        startActivityForResult(new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/json")
                            .addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE, "timed-memo-diagnostics.json"), 104);
                    }
                    case "importBackup" -> {
                        if (documentResult != null) throw new IllegalStateException("文件操作处理中");
                        documentResult = result;
                        startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*")
                            .addCategory(Intent.CATEGORY_OPENABLE), 105);
                    }
                    default -> result.notImplemented();
                }
            } catch (Exception e) {
                if (ringtoneResult == result) ringtoneResult = null;
                if (documentResult == result) { documentResult = null; exportDocument = null; }
                result.error("NATIVE", e.getMessage(), null);
            }
        });
    }
    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] grants) {
        super.onRequestPermissionsResult(request, permissions, grants);
        if ((request == 101 || request == 102) && permissionResult != null) {
            MethodChannel.Result result = permissionResult; permissionResult = null;
            boolean granted = grants.length > 0 && grants[0] == PackageManager.PERMISSION_GRANTED;
            try {
                if (request == 102) {
                    if (!granted) throw new IllegalStateException("请在系统设置中允许麦克风权限");
                    startRecording(); result.success(null);
                } else result.success(granted);
            } catch (Exception e) { result.error("PERMISSION", e.getMessage(), null); }
        }
    }
    private void stopSpeechPreview() {
        if (speechPreview != null) { speechPreview.release(); speechPreview = null; }
    }
    @Override protected void onResume() {
        super.onResume(); resumed = true; foreground = new java.lang.ref.WeakReference<>(this);
        ReminderEngine engine = new ReminderEngine(this);
        try { engine.refreshNotifications(); }
        catch (Exception e) { engine.error("更新通知正文失败：" + e.getClass().getSimpleName()); }
    }
    @SuppressWarnings("deprecation")
    @Override protected void onActivityResult(int request, int resultCode, Intent data) {
        super.onActivityResult(request, resultCode, data);
        if (request == 103 && ringtoneResult != null) {
            Uri uri = resultCode == Activity.RESULT_OK && data != null
                ? data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI) : null;
            ringtoneResult.success(uri == null ? null : uri.toString()); ringtoneResult = null;
        }
        if ((request == 104 || request == 105) && documentResult != null) {
            final MethodChannel.Result result = documentResult;
            final String backup = exportDocument;
            documentResult = null; exportDocument = null;
            final Uri uri = resultCode == Activity.RESULT_OK && data != null ? data.getData() : null;
            if (uri == null) { result.success(null); return; }
            documents.execute(() -> {
                try {
                    if (request == 104) {
                        try (OutputStream output = getContentResolver().openOutputStream(uri, "wt")) {
                            if (output == null) throw new IOException("无法写入文件");
                            output.write(backup.getBytes(java.nio.charset.StandardCharsets.UTF_8)); output.flush();
                        }
                        runOnUiThread(() -> result.success(true));
                    } else {
                        String source;
                        try (InputStream input = getContentResolver().openInputStream(uri);
                             ByteArrayOutputStream bytes = new ByteArrayOutputStream()) {
                            if (input == null) throw new IOException("无法读取文件");
                            byte[] buffer = new byte[8192]; int count;
                            while ((count = input.read(buffer)) != -1) {
                                if (bytes.size() + count > BackupCodec.MAX_BYTES) throw new IOException("备份文件不能超过8MB");
                                bytes.write(buffer, 0, count);
                            }
                            source = bytes.toString(java.nio.charset.StandardCharsets.UTF_8.name());
                        }
                        final String json = source;
                        runOnUiThread(() -> {
                            try { result.success(new ReminderEngine(this).importBackup(json)); }
                            catch (Exception e) { result.error("IMPORT", "导入失败，原有数据保留：" + e.getMessage(), null); }
                        });
                    }
                } catch (Exception e) { runOnUiThread(() -> result.error("DOCUMENT", e.getMessage(), null)); }
            });
        }
    }
    private void startRecording() throws IOException {
        stopSpeechPreview();
        SpeechPlaybackService.pauseForRecording();
        if (recording) throw new IllegalStateException("已在录音");
        int buffer = Math.max(6400, AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT));
        recorder = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, buffer);
        if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
            recorder.release(); recorder = null;
            throw new IOException("麦克风初始化失败，可能被其他应用占用");
        }
        audioFile = new File(getCacheDir(), "memo-recording.pcm");
        FileOutputStream output = new FileOutputStream(audioFile);
        audioError = null;
        try { recorder.startRecording(); }
        catch (RuntimeException e) { output.close(); recorder.release(); recorder = null; throw e; }
        recording = true;
        final AudioRecord source = recorder;
        audioThread = new Thread(() -> {
            try (FileOutputStream out = output) {
                short[] samples = new short[1600];
                byte[] bytes = new byte[3200];
                int total = 0;
                while (recording && total < 16000 * 45) {
                    int count = source.read(samples, 0, samples.length);
                    if (count < 0) throw new IOException("录音设备读入失败");
                    for (int i = 0; i < count; i++) {
                        bytes[i * 2] = (byte) samples[i]; bytes[i * 2 + 1] = (byte) (samples[i] >> 8);
                    }
                    out.write(bytes, 0, count * 2); total += count;
                }
            } catch (Exception e) { if (recording) audioError = e.getMessage(); }
        }, "memo-audio");
        audioThread.start();
    }
    private String stopRecording(boolean discard) throws IOException, InterruptedException {
        if (recorder == null) return null;
        recording = false;
        try { recorder.stop(); } catch (IllegalStateException ignored) {}
        if (audioThread != null) audioThread.join(2000);
        recorder.release(); recorder = null; audioThread = null;
        String path = audioFile == null ? null : audioFile.getAbsolutePath();
        if (discard) { if (audioFile != null) audioFile.delete(); return null; }
        if (audioError != null) { if (audioFile != null) audioFile.delete(); throw new IOException(audioError); }
        return path;
    }
    @Override protected void onPause() {
        resumed = false; if (reminderDialog != null) { reminderDialog.dismiss(); reminderDialog = null; }
        super.onPause(); stopSpeechPreview();
    }
    @Override protected void onStop() {
        super.onStop();
        try { stopRecording(true); } catch (Exception ignored) {}
    }
    @Override protected void onDestroy() {
        if (memoPreferences != null && memoListener != null) memoPreferences.unregisterOnSharedPreferenceChangeListener(memoListener);
        super.onDestroy();
        documents.shutdown();
    }
    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent); setIntent(intent);
        if (channel != null && intent.hasExtra("reminderId")) channel.invokeMethod("openReminder", intent.getIntExtra("reminderId", 0));
    }
}
