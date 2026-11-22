package com.niceday.memo;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;

/**
 * Encapsulates Android system-settings navigation extracted from MainActivity.
 * Adds graceful fallback to app details when OEM ROMs omit battery-whitelist screens.
 */
final class DeviceSettingsNavigator {
  private DeviceSettingsNavigator() {}

  static Intent notificationSettingsIntent(String packageName) {
    return new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName);
  }

  static Intent batterySettingsIntent() {
    return new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
  }

  static Intent appSettingsIntent(String packageName) {
    return new Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:" + packageName));
  }

  static Intent channelSettingsIntent(String packageName, String channelId) {
    return new Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        .putExtra(Settings.EXTRA_CHANNEL_ID, channelId);
  }

  static void openNotificationSettings(Context context) {
    startWithFallback(
        context,
        notificationSettingsIntent(context.getPackageName()),
        appSettingsIntent(context.getPackageName()));
  }

  static void openBatterySettings(Context context) {
    startWithFallback(
        context,
        batterySettingsIntent(),
        appSettingsIntent(context.getPackageName()));
  }

  static void openAppSettings(Context context) {
    context.startActivity(appSettingsIntent(context.getPackageName()));
  }

  static void openChannelSettings(Context context, String channelId) {
    startWithFallback(
        context,
        channelSettingsIntent(context.getPackageName(), channelId),
        notificationSettingsIntent(context.getPackageName()));
  }

  private static void startWithFallback(Context context, Intent primary, Intent fallback) {
    try {
      context.startActivity(primary);
    } catch (ActivityNotFoundException ignored) {
      context.startActivity(fallback);
    }
  }
}
