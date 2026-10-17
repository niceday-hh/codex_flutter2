package com.niceday.memo;
import org.json.*;

/** Foreground voice session preferences, separate from alarm delivery state. */
public final class VoiceInputSettings {
    private VoiceInputSettings() {}
    public static void validate(JSONObject r) throws JSONException {
        for(String key:new String[]{"handsFree","voiceAutoStop"})
            if(r.has(key) && !(r.get(key) instanceof Boolean)) throw new IllegalArgumentException("语音输入开关无效");
        if(r.has("voiceSilenceSeconds")) {
            Object n=r.get("voiceSilenceSeconds");
            if(!(n instanceof Integer || n instanceof Long) || ((Number)n).intValue()<3 || ((Number)n).intValue()>10)
                throw new IllegalArgumentException("静音停录须为3至10秒");
        }
        r.put("handsFree",r.optBoolean("handsFree",false)).put("voiceAutoStop",r.optBoolean("voiceAutoStop",true))
            .put("voiceSilenceSeconds",r.optInt("voiceSilenceSeconds",5));
    }
}
