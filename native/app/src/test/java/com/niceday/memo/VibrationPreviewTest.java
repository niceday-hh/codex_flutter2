package com.niceday.memo;

import android.app.NotificationManager;
import android.content.Context;
import android.os.Build;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.provider.Settings;
import org.json.JSONObject;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = {26, 33})
public class VibrationPreviewTest {
    Context context;
    Vibrator vibrator;
    @Before public void setup() {
        context = RuntimeEnvironment.getApplication();
        vibrator = Build.VERSION.SDK_INT >= 31
            ? context.getSystemService(VibratorManager.class).getDefaultVibrator()
            : context.getSystemService(Vibrator.class);
        Shadows.shadowOf(vibrator).setHasVibrator(true);
        Settings.System.putInt(context.getContentResolver(), Settings.System.HAPTIC_FEEDBACK_ENABLED, 1);
    }
    @Test public void previewRequestsTheSelectedFinitePatternWithoutCreatingNotificationChannels() throws Exception {
        NotificationManager notifications = context.getSystemService(NotificationManager.class);
        int channels = notifications.getNotificationChannels().size();
        JSONObject result = NotificationStyles.preview(context, "three");
        assertTrue(result.getBoolean("requested"));
        assertEquals(3, result.getInt("pulses")); assertEquals(1000, result.getLong("durationMs"));
        assertTrue(Shadows.shadowOf(vibrator).isVibrating());
        assertArrayEquals(new long[]{0, 200, 200, 200, 200, 200}, Shadows.shadowOf(vibrator).getPattern());
        assertEquals(channels, notifications.getNotificationChannels().size());
    }
    @Test public void disabledTouchFeedbackDoesNotBlockReminderPreviewOrChangeTheSystemSetting() throws Exception {
        Settings.System.putInt(context.getContentResolver(), Settings.System.HAPTIC_FEEDBACK_ENABLED, 0);
        assertTrue(NotificationStyles.preview(context, "once").getBoolean("requested"));
        assertTrue(Shadows.shadowOf(vibrator).isVibrating());
        assertArrayEquals(new long[]{0, 250}, Shadows.shadowOf(vibrator).getPattern());
        assertEquals(0, Settings.System.getInt(context.getContentResolver(), Settings.System.HAPTIC_FEEDBACK_ENABLED));
    }
    @Test public void missingHardwareIsNotReportedAsASuccessfulRequest() throws Exception {
        Shadows.shadowOf(vibrator).setHasVibrator(false);
        try { NotificationStyles.preview(context, "once"); fail("No hardware must be explained"); }
        catch (IllegalStateException expected) { assertTrue(expected.getMessage().contains("没有可用振动器")); }
    }
    @Test public void systemAndOffModesAreNotInventedPreviewPatterns() throws Exception {
        for (String mode : new String[]{"system", "off"}) {
            try { NotificationStyles.preview(context, mode); fail("No invented system pattern"); }
            catch (IllegalArgumentException expected) { assertTrue(expected.getMessage().contains("15秒通知测试")); }
        }
        assertFalse(Shadows.shadowOf(vibrator).isVibrating());
    }
}
