package com.niceday.memo;
import android.content.Context;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=33)
public class VoiceCatalogTest {
    @Test public void poolsHaveRealIdsAndExcludeUnclassifiedGender() throws Exception {
        Context c=RuntimeEnvironment.getApplication();
        assertEquals(804,VoiceCatalog.candidates(c,"all","all").size());
        assertTrue(VoiceCatalog.candidates(c,"ja","female").contains("303"));
        assertTrue(VoiceCatalog.candidates(c,"zh","male").contains("104"));
        assertFalse(VoiceCatalog.candidates(c,"all","female").contains("803"));
        JSONObject row=new JSONObject().put("speechRandom",true).put("speechRandomLanguage","ja").put("speechRandomGender","male");
        SpeechSettings.validate(row,false); VoiceCatalog.resolve(c,row);
        String selected=row.getString("speechVoice");
        assertTrue(VoiceCatalog.candidates(c,"ja","male").contains(selected));
        VoiceCatalog.resolve(c,row); assertEquals(selected,row.getString("speechVoice"));
    }
    @Test public void invalidRandomRulesAreRejectedBeforeSaving() throws Exception {
        for(JSONObject r: new JSONObject[]{new JSONObject().put("speechRandom","true"),new JSONObject().put("speechRandomLanguage","ko"),new JSONObject().put("speechRandomGender",3)}) {
            try { SpeechSettings.validate(r,false); fail("Invalid random rule accepted"); } catch(IllegalArgumentException expected) {}
        }
    }
}
