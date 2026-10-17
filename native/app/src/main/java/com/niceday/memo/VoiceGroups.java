package com.niceday.memo;

import android.content.Context;
import org.json.*;
import java.util.*;

/** User groups contain stable speaker IDs, never model files or executable paths. */
public final class VoiceGroups {
    private VoiceGroups() {}
    public static JSONArray read(Context c) throws JSONException {
        return validate(new JSONArray(c.getSharedPreferences("memo",0).getString("voiceGroups","[]")));
    }
    public static JSONArray validate(JSONArray input) throws JSONException {
        if(input.length()>50) throw new IllegalArgumentException("最多创建50个角色组");
        JSONArray clean=new JSONArray(); Set<String> ids=new HashSet<>();
        for(int i=0;i<input.length();i++) {
            JSONObject g=input.getJSONObject(i);
            if(!(g.get("id") instanceof String) || !(g.get("name") instanceof String)) throw new IllegalArgumentException("角色组格式无效");
            String id=g.getString("id"), name=g.getString("name").trim();
            if(!id.matches("[A-Za-z0-9_-]{1,80}") || !ids.add(id) || name.isEmpty() || name.length()>30)
                throw new IllegalArgumentException("角色组名称或编号无效");
            JSONArray voices=g.getJSONArray("voices"), selected=new JSONArray(); Set<String> unique=new HashSet<>();
            if(voices.length()==0 || voices.length()>804) throw new IllegalArgumentException("角色组须包含1至804个角色");
            for(int j=0;j<voices.length();j++) {
                Object value=voices.get(j);
                if(!(value instanceof String) || !((String)value).matches("(0|[1-9][0-9]{0,2})") || Integer.parseInt((String)value)>803 || !unique.add((String)value))
                    throw new IllegalArgumentException("角色组包含无效或重复音色");
                selected.put(value);
            }
            clean.put(new JSONObject().put("id",id).put("name",name).put("voices",selected));
        }
        return clean;
    }
    public static void save(Context c, String source) throws JSONException {
        JSONArray groups=validate(new JSONArray(source));
        android.content.SharedPreferences prefs=c.getSharedPreferences("memo",0);
        JSONObject defaults=new JSONObject(prefs.getString("defaults","{}"));
        if(!defaults.optString("speechRandomGroup").isEmpty() && members(groups,defaults.optString("speechRandomGroup"))==null)
            defaults.put("speechRandomGroup","").put("speechRandom",false);
        if(!prefs.edit().putString("voiceGroups",groups.toString()).putString("defaults",defaults.toString()).commit())
            throw new IllegalStateException("角色组保存失败");
    }
    public static Set<String> members(JSONArray groups,String id) throws JSONException {
        for(int i=0;i<groups.length();i++) if(id.equals(groups.getJSONObject(i).getString("id"))) {
            Set<String> result=new HashSet<>(); JSONArray voices=groups.getJSONObject(i).getJSONArray("voices");
            for(int j=0;j<voices.length();j++) result.add(voices.getString(j));
            return result;
        }
        return null;
    }
}
