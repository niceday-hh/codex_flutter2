package com.niceday.memo;
import android.content.*;
import org.json.*;

/** CI-only probe. This receiver is absent from the release APK. */
public final class DebugAlarmProbe extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        try {
            ReminderEngine engine = new ReminderEngine(context);
            if ("CLEAR".equals(intent.getAction())) {
                JSONArray rows = new JSONObject(engine.state()).getJSONArray("reminders");
                for (int i = 0; i < rows.length(); i++) engine.delete(rows.getJSONObject(i).getInt("id"));
            } else {
                int id = engine.createTest(intent.getIntExtra("seconds", 15));
                setResultCode(id);
            }
        } catch (Exception e) { throw new IllegalStateException(e); }
    }
}
