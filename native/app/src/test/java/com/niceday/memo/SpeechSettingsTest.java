package com.niceday.memo;

import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class SpeechSettingsTest {
    @Test public void screenOffProtectsBodyBeforeKeyguardFinishesLocking() {
        android.content.Context c = org.robolectric.RuntimeEnvironment.getApplication();
        org.robolectric.Shadows.shadowOf(c.getSystemService(android.app.KeyguardManager.class)).setKeyguardLocked(false);
        org.robolectric.Shadows.shadowOf(c.getSystemService(android.os.PowerManager.class)).setIsInteractive(false);
        assertTrue(SpeechPlaybackService.privacyLocked(c));
        org.robolectric.Shadows.shadowOf(c.getSystemService(android.os.PowerManager.class)).setIsInteractive(true);
        assertFalse(SpeechPlaybackService.privacyLocked(c));
    }
    @Test public void legacyOffAndExplicitOverridesDefault() throws Exception {
        JSONObject defaults = new JSONObject().put("speechMode", "on");
        assertFalse(SpeechSettings.enabled(new JSONObject(), defaults));
        assertTrue(SpeechSettings.enabled(new JSONObject().put("speechMode", "inherit"), defaults));
        assertFalse(SpeechSettings.enabled(new JSONObject().put("speechMode", "off"), defaults));
        assertTrue(SpeechSettings.enabled(new JSONObject().put("speechMode", "on"), new JSONObject()));
    }
    @Test public void acceptsActualSpeakerRangeAndPreservesPrivacyOff() throws Exception {
        JSONObject r = new JSONObject().put("speechMode", "on").put("speechVoice", "803").put("speechRate", 1.3).put("speechHideLocked", false);
        SpeechSettings.validate(r, false);
        assertFalse(SpeechSettings.hideLocked(r, new JSONObject()));
        for (String voice : new String[]{"804", "-1", "bili22", "../../file"}) {
            try { SpeechSettings.validate(new JSONObject().put("speechVoice", voice), false); fail(voice); }
            catch (IllegalArgumentException expected) {}
        }
        for (Object rate : new Object[]{0.4, 1.4, "1.0"}) {
            try { SpeechSettings.validate(new JSONObject().put("speechRate", rate), false); fail(String.valueOf(rate)); }
            catch (IllegalArgumentException expected) {}
        }
    }
    @Test public void voiceAndRateInheritAndAffectCacheIdentity() throws Exception {
        JSONObject slow = new JSONObject().put("speechRate", .5);
        SpeechSettings.validate(slow, false);
        assertEquals(.5, slow.getDouble("speechRate"), .0001);
        JSONObject defaults = new JSONObject().put("speechVoice", "33").put("speechRate", 0.9);
        assertEquals("33", SpeechSettings.voice(new JSONObject(), defaults));
        assertEquals(0.9, SpeechSettings.rate(new JSONObject(), defaults), 0.0001);
        String key = SpeechSettings.cacheKey("喝水", "33", 1);
        assertTrue(key.matches("[0-9a-f]{64}"));
        assertNotEquals(key, SpeechSettings.cacheKey("喝水", "34", 1));
        assertNotEquals(key, SpeechSettings.cacheKey("喝水", "33", 1.1));
        assertNotEquals(key, SpeechSettings.cacheKey("吃药", "33", 1));
    }
    @Test public void variationDefaultsValidationAndIdentityAreExplicit() throws Exception {
        JSONObject row = new JSONObject(), defaults = new JSONObject().put("speechNoiseScale", .4).put("speechNoiseScaleW", .7);
        SpeechSettings.validate(row, false);
        assertEquals(.4, SpeechSettings.noise(row, defaults), .00001);
        assertEquals(.7, SpeechSettings.noiseW(row, defaults), .00001);
        row.put("speechNoiseScale", .6).put("speechNoiseScaleW", .668);
        assertEquals(.6, SpeechSettings.noise(row, defaults), .00001);
        String key = SpeechSettings.cacheKey("喝水", "228", .8, .6, .668, 123);
        assertNotEquals(key, SpeechSettings.cacheKey("喝水", "228", .8, .4, .668, 123));
        assertNotEquals(key, SpeechSettings.cacheKey("喝水", "228", .8, .6, .5, 123));
        assertNotEquals(key, SpeechSettings.cacheKey("喝水", "228", .8, .6, .668, 124));
        for (Object bad : new Object[]{"0.6", -.1, .09, 1.1, JSONObject.NULL}) {
            for (String field : new String[]{"speechNoiseScale", "speechNoiseScaleW"}) {
                try { SpeechSettings.validate(new JSONObject().put(field, bad), false); fail(); }
                catch (IllegalArgumentException expected) {}
            }
        }
        for (Object bad : new Object[]{1.5, -1, 2147483648L, "1"}) {
            try { SpeechSettings.validate(new JSONObject().put("speechSeed", bad), false); fail(); }
            catch (IllegalArgumentException expected) {}
        }
    }
}
