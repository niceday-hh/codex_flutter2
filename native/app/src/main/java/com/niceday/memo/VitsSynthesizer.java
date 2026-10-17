package com.niceday.memo;

import android.content.Context;
import com.niceday.memo.tts.ChineseTextUtils;
import org.json.*;
import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Runs on the documents executor. Streams PCM to disk instead of joining long arrays. */
final class VitsSynthesizer {
    private ChineseTextUtils cleaner;
    private boolean opened;
    void open(Context c, String directory) throws Exception {
        JSONObject config = new JSONObject(new String(java.nio.file.Files.readAllBytes(new File(directory, "config.json").toPath()), StandardCharsets.UTF_8));
        if (config.getJSONArray("speakers").length() != 804 || config.getJSONObject("data").getInt("sampling_rate") != 22050)
            throw new IOException("播报模型元信息不匹配");
        List<String> symbols = new ArrayList<>(); JSONArray values = config.getJSONArray("symbols");
        for (int i=0;i<values.length();i++) symbols.add(values.getString(i));
        cleaner = new ChineseTextUtils(symbols, "chinese_cleaners", c.getAssets()); cleaner.initPinyinEngine();
        VitsMnn.open(directory); opened=true;
    }
    void generate(Context c, JSONObject job) throws Exception {
        String key = job.getString("key"), text = job.getString("text");
        if (cleaner == null || !SpeechCache.pending(key)) throw new IllegalArgumentException("语音任务已失效");
        int speaker = job.getInt("sid"); float rate = (float)job.getDouble("rate");
        File temporary = new File(SpeechCache.directory(c), key+".part");
        try (RandomAccessFile output = new RandomAccessFile(temporary,"rw")) {
            output.setLength(0); output.write(new byte[44]); long samples=0;
            for (int start=0;start<text.length();) {
                int end=text.offsetByCodePoints(start,Math.min(24,text.codePointCount(start,text.length())));
                String chunk=text.substring(start,end); start=end;
                for (int[] labels : cleaner.convertText(chunk)) {
                    if (labels.length < 3) continue;
                    float[] audio=VitsMnn.generate(labels,speaker,rate);
                    if (audio==null || audio.length==0) throw new IOException("未生成有效语音");
                    samples+=audio.length; if(samples>22050L*900) throw new IOException("播报超过15分钟");
                    ByteBuffer pcm=ByteBuffer.allocate(8192).order(ByteOrder.LITTLE_ENDIAN);
                    for(float value:audio) {
                        if(!Float.isFinite(value)) throw new IOException("无效的音频采样");
                        pcm.putShort((short)Math.round(Math.max(-1,Math.min(1,value))*32767));
                        if(!pcm.hasRemaining()) { output.write(pcm.array()); pcm.clear(); }
                    }
                    if(pcm.position()>0) output.write(pcm.array(),0,pcm.position());
                }
            }
            if(samples==0) throw new IOException("正文没有可朗读的文字");
            int bytes=(int)(samples*2);
            ByteBuffer header=ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
            header.put("RIFF".getBytes(StandardCharsets.US_ASCII)).putInt(bytes+36).put("WAVEfmt ".getBytes(StandardCharsets.US_ASCII))
                .putInt(16).putShort((short)1).putShort((short)1).putInt(22050).putInt(44100).putShort((short)2).putShort((short)16)
                .put("data".getBytes(StandardCharsets.US_ASCII)).putInt(bytes);
            output.seek(0); output.write(header.array()); output.getFD().sync();
        } catch(Exception e) { temporary.delete(); throw e; }
    }
    void close() { cleaner=null; if(opened) { opened=false; VitsMnn.close(); } }
}
