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
        if(r.has("asrBackgroundRetentionSeconds")) {
            Object n=r.get("asrBackgroundRetentionSeconds");
            if(!(n instanceof Integer || n instanceof Long))
                throw new IllegalArgumentException("模型后台保留时长须为0、15、30或60秒");
            long seconds=((Number)n).longValue();
            if(seconds!=0 && seconds!=15 && seconds!=30 && seconds!=60)
                throw new IllegalArgumentException("模型后台保留时长须为0、15、30或60秒");
        }
        r.put("handsFree",r.optBoolean("handsFree",false)).put("voiceAutoStop",r.optBoolean("voiceAutoStop",true))
            .put("voiceSilenceSeconds",r.optInt("voiceSilenceSeconds",5))
            .put("asrBackgroundRetentionSeconds",r.optInt("asrBackgroundRetentionSeconds",30));
    }
}
