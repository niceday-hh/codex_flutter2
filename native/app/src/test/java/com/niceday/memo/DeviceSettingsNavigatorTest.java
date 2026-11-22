package com.niceday.memo;

import static org.junit.Assert.assertEquals;

import android.content.Intent;
import android.provider.Settings;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class DeviceSettingsNavigatorTest {
  private static final String PKG = "com.niceday.memo.stable";

  @Test
  public void buildsNotificationSettingsIntentWithPackageExtra() {
    Intent intent = DeviceSettingsNavigator.notificationSettingsIntent(PKG);
    assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, intent.getAction());
    assertEquals(PKG, intent.getStringExtra(Settings.EXTRA_APP_PACKAGE));
  }

  @Test
  public void buildsChannelSettingsIntentWithPackageAndChannelExtra() {
    Intent intent = DeviceSettingsNavigator.channelSettingsIntent(PKG, "memo_urgent");
    assertEquals(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS, intent.getAction());
    assertEquals(PKG, intent.getStringExtra(Settings.EXTRA_APP_PACKAGE));
    assertEquals("memo_urgent", intent.getStringExtra(Settings.EXTRA_CHANNEL_ID));
  }

  @Test
  public void buildsAppSettingsIntentWithPackageUri() {
    Intent intent = DeviceSettingsNavigator.appSettingsIntent(PKG);
    assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, intent.getAction());
    assertEquals("package:" + PKG, intent.getDataString());
  }
}
