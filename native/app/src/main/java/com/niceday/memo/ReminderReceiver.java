package com.niceday.memo;
import android.content.*;

public final class ReminderReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        ReminderEngine engine = new ReminderEngine(context);
        try {
            String action = intent.getAction();
            if (ReminderEngine.ACK.equals(action)) {
                engine.acknowledge(intent.getIntExtra("id", 0), intent.getLongExtra("token", 0));
            } else if (ReminderEngine.BASE.equals(action) || ReminderEngine.RETRY.equals(action)) {
                engine.fire(intent);
            } else {
                boolean changed = Intent.ACTION_TIME_CHANGED.equals(action) || Intent.ACTION_TIMEZONE_CHANGED.equals(action);
                engine.restore(changed);
            }
        } catch (Exception e) { engine.error("提醒处理失败：" + e.getClass().getSimpleName()); }
    }
}
