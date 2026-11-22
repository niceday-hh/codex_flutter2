package com.niceday.memo;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.KeyguardManager;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.view.Window;
import android.view.WindowManager;
import org.json.JSONObject;

/**
 * Lifecycle-safe foreground reminder dialog presenter extracted from MainActivity.
 * Cancels pending auto-dismiss callbacks on manual dismissal or activity teardown
 * to prevent WindowLeaked / View-not-attached exceptions.
 */
final class ReminderDialogPresenter {
  private static final long AUTO_DISMISS_MS = 10_000L;

  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private AlertDialog activeDialog;
  private Runnable pendingDismiss;

  boolean canPresent(Activity activity, boolean resumed) {
    if (activity == null || !resumed || activity.isFinishing() || activity.isDestroyed()) {
      return false;
    }
    KeyguardManager keyguard = activity.getSystemService(KeyguardManager.class);
    PowerManager power = activity.getSystemService(PowerManager.class);
    if (keyguard != null && keyguard.isKeyguardLocked()) return false;
    return power == null || power.isInteractive();
  }

  boolean show(Activity activity, boolean resumed, JSONObject reminder, long token) {
    if (!canPresent(activity, resumed)) return false;
    activity.runOnUiThread(() -> {
      if (!canPresent(activity, resumed)) return;
      dismiss();

      AlertDialog dialog = new AlertDialog.Builder(activity)
          .setTitle("超级提醒")
          .setMessage(reminder.optString("text"))
          .setNegativeButton("收起", null)
          .setPositiveButton("已读", (d, which) -> {
            try {
              new ReminderEngine(activity).acknowledge(reminder.optInt("id"), token);
            } catch (Exception e) {
              new ReminderEngine(activity).error("确认已读失败，请在通知栏重试");
            }
          })
          .create();

      dialog.setOnDismissListener(d -> clearPendingDismiss());
      activeDialog = dialog;
      dialog.show();

      Window window = dialog.getWindow();
      if (window != null) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE);
      }

      pendingDismiss = () -> {
        if (!activity.isFinishing() && !activity.isDestroyed() && dialog.isShowing()) {
          dialog.dismiss();
        }
      };
      mainHandler.postDelayed(pendingDismiss, AUTO_DISMISS_MS);
    });
    return true;
  }

  void dismiss() {
    clearPendingDismiss();
    if (activeDialog != null) {
      if (activeDialog.isShowing()) {
        activeDialog.dismiss();
      }
      activeDialog = null;
    }
  }

  private void clearPendingDismiss() {
    if (pendingDismiss != null) {
      mainHandler.removeCallbacks(pendingDismiss);
      pendingDismiss = null;
    }
  }
}
