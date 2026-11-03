package com.niceday.memo;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class VoiceInputSettingsTest {
    @Test public void missingRetentionMigratesToThirtySeconds() throws Exception {
        JSONObject values = new JSONObject();
        VoiceInputSettings.validate(values);
        assertEquals(30, values.getInt("asrBackgroundRetentionSeconds"));
        assertFalse(values.getBoolean("handsFree"));
    }
    @Test public void retentionOnlyAcceptsTheFourOfferedDurations() throws Exception {
        for (int seconds : new int[]{0, 15, 30, 60}) {
            JSONObject values = new JSONObject().put("asrBackgroundRetentionSeconds", seconds);
            VoiceInputSettings.validate(values);
            assertEquals(seconds, values.getInt("asrBackgroundRetentionSeconds"));
        }
        for (Object invalid : new Object[]{-1, 20, 120, 30.5, "30", true, JSONObject.NULL, 4294967326L}) {
            JSONObject values = new JSONObject().put("asrBackgroundRetentionSeconds", invalid);
            try {
                VoiceInputSettings.validate(values);
                fail("Accepted invalid model retention: " + invalid);
            } catch (IllegalArgumentException expected) {
                assertTrue(expected.getMessage().contains("0、15、30或60"));
            }
        }
    }
}
