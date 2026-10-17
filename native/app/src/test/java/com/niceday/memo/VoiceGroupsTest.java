package com.niceday.memo;
import android.content.Context;
import org.json.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=33)
public class VoiceGroupsTest {
    private JSONObject group(String id,String... voices) throws Exception {
        return new JSONObject().put("id",id).put("name","喜欢的角色").put("voices",new JSONArray(voices));
    }
    @Test public void customPoolPersistsAndOldChoiceSurvivesGroupChanges() throws Exception {
        Context c=RuntimeEnvironment.getApplication();
        VoiceGroups.save(c,new JSONArray().put(group("favourites","228","303")).toString());
        JSONObject row=new JSONObject().put("speechRandom",true).put("speechRandomGroup","favourites").put("speechVoice","");
        SpeechSettings.validate(row,false); VoiceCatalog.resolve(c,row);
        String selected=row.getString("speechVoice");
        assertTrue(selected.equals("228")||selected.equals("303"));
        VoiceGroups.save(c,new JSONArray().put(group("favourites","104")).toString());
        VoiceCatalog.resolve(c,row); assertEquals(selected,row.getString("speechVoice"));
        VoiceGroups.save(c,"[]"); VoiceCatalog.resolve(c,row);
        assertEquals(selected,row.getString("speechVoice"));
        row.put("speechVoice","");
        try { VoiceCatalog.resolve(c,row); fail("Deleted group must not silently choose any voice"); } catch(IllegalArgumentException expected) {}
    }
    @Test public void sourceAndGenderAreIntersectedWithCustomGroup() throws Exception {
        Context c=RuntimeEnvironment.getApplication();
        VoiceGroups.save(c,new JSONArray().put(group("mixed","104","303")).toString());
        JSONObject row=new JSONObject().put("speechRandom",true).put("speechRandomGroup","mixed")
            .put("speechRandomLanguage","ja").put("speechRandomGender","female");
        SpeechSettings.validate(row,false); VoiceCatalog.resolve(c,row); assertEquals("303",row.getString("speechVoice"));
        row.put("speechVoice","").put("speechRandomGender","male");
        try { VoiceCatalog.resolve(c,row); fail("Empty intersection accepted"); } catch(IllegalArgumentException expected) {}
    }
    @Test public void malformedGroupsAndSettingsAreRejected() throws Exception {
        for(JSONArray groups:new JSONArray[]{
            new JSONArray().put(group("g","804")),new JSONArray().put(group("g","1","1")),
            new JSONArray().put(group("g")),new JSONArray().put(group("g","1")).put(group("g","2"))}) {
            try { VoiceGroups.validate(groups); fail("Malformed group accepted"); } catch(IllegalArgumentException expected) {}
        }
        for(JSONObject settings:new JSONObject[]{new JSONObject().put("handsFree","yes"),new JSONObject().put("voiceSilenceSeconds",0),new JSONObject().put("voiceSilenceSeconds",5.5)}) {
            try { VoiceInputSettings.validate(settings); fail("Malformed input setting accepted"); } catch(IllegalArgumentException expected) {}
        }
    }
    @Test public void importClonesCollidingGroupsAndKeepsSelectedVoice() throws Exception {
        Context c=RuntimeEnvironment.getApplication();
        VoiceGroups.save(c,new JSONArray().put(group("same","104")).toString());
        ReminderEngine engine=new ReminderEngine(c);
        JSONObject row=new JSONObject().put("text","导入角色组测试").put("year",2099).put("month",1).put("day",1)
            .put("hour",10).put("minute",0).put("enabled",false).put("speechRandom",true).put("speechRandomGroup","same")
            .put("speechVoice","303").put("speechModel","voine-vits-mnn-v1");
        JSONObject source=new JSONObject().put("format","timed-memo").put("version",1)
            .put("reminders",new JSONArray().put(row)).put("voiceGroups",new JSONArray().put(group("same","303")));
        assertEquals(1,engine.importBackup(source.toString()));
        JSONArray groups=VoiceGroups.read(c); assertEquals(2,groups.length());
        assertTrue(VoiceGroups.members(groups,"same").contains("104"));
        JSONObject imported=new JSONObject(engine.state()).getJSONArray("reminders").getJSONObject(0);
        assertNotEquals("same",imported.getString("speechRandomGroup"));
        assertEquals("303",imported.getString("speechVoice"));
        assertEquals(2,new JSONObject(engine.exportBackup()).getJSONArray("voiceGroups").length());
    }
}
