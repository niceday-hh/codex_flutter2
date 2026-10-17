package com.niceday.memo;

import android.content.Context;
import org.json.*;
import java.io.*;
import java.util.*;

/** Offline role metadata. Unknown genders are never guessed from a name. */
public final class VoiceCatalog {
    private static JSONArray cached;
    private VoiceCatalog() {}
    private static synchronized JSONArray entries(Context c) throws Exception {
        if (cached == null) {
            try (InputStream in = c.getAssets().open("voice_catalog.json")) {
                ByteArrayOutputStream bytes=new ByteArrayOutputStream(); byte[] buffer=new byte[4096]; int n;
                while((n=in.read(buffer))!=-1) bytes.write(buffer,0,n);
                cached = new JSONObject(bytes.toString("UTF-8")).getJSONArray("voices");
                if (cached.length() != 804) { cached=null; throw new IOException("音色分组资料不完整"); }
            }
        }
        return cached;
    }
    public static List<String> candidates(Context c, String language, String gender) throws Exception {
        JSONArray voices=entries(c); List<String> result=new ArrayList<>();
        for(int i=0;i<voices.length();i++) {
            JSONObject v=voices.getJSONObject(i);
            if (("all".equals(language)||language.equals(v.getString("language"))) &&
                ("all".equals(gender)||gender.equals(v.getString("gender")))) result.add(Integer.toString(i));
        }
        return result;
    }
    static void resolve(Context c, JSONObject row) throws JSONException {
        try {
        if (!row.optBoolean("speechRandom")) return;
        List<String> pool=candidates(c,row.optString("speechRandomLanguage","all"),row.optString("speechRandomGender","all"));
        if(pool.isEmpty()) throw new IllegalArgumentException("此分组没有可随机选择的音色，请调整分组");
        if(!pool.contains(row.optString("speechVoice")))
            row.put("speechVoice",pool.get(java.util.concurrent.ThreadLocalRandom.current().nextInt(pool.size())));
        } catch (JSONException e) { throw e; }
        catch (Exception e) { throw new IllegalArgumentException("无法随机选择音色，请检查分组后重试",e); }
    }
}
