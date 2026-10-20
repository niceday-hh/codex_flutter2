package com.niceday.memo;

import android.content.Context;
import com.niceday.memo.tts.ChineseTextUtils;
import com.niceday.memo.tts.PreparedText;
import com.niceday.memo.tts.SpeechSegmenter;
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
            output.setLength(0); output.write(new byte[44]); long samples=0; double peak=0;
            ArrayDeque<SpeechSegmenter.Segment> chunks = new ArrayDeque<>(SpeechSegmenter.split(text));
            while (!chunks.isEmpty()) {
                SpeechSegmenter.Segment segment = chunks.removeFirst();
                PreparedText prepared = cleaner.encode(segment.text, segment.terminal());
                int[] labels = prepared.getLabels(), pauses = prepared.getPauses();
                if (labels.length > 640) {
                    int count = segment.text.codePointCount(0, segment.text.length());
                    if (count <= 1) throw new IOException("单个文本单元超过合成上限");
                    List<SpeechSegmenter.Segment> smaller = SpeechSegmenter.split(segment.text, Math.max(1, count / 2));
                    for (int i = smaller.size() - 1; i >= 0; i--) {
                        SpeechSegmenter.Segment child = smaller.get(i);
                        int boundary = i == smaller.size() - 1 ? segment.boundary : SpeechSegmenter.punctuation(child.text.codePointBefore(child.text.length()));
                        chunks.addFirst(new SpeechSegmenter.Segment(child.text, boundary));
                    }
                    continue;
                }
                {
                    if (labels.length < 3) continue;
                    if (segment.boundary == SpeechSegmenter.PARAGRAPH) {
                        for (int i = pauses.length - 1; i >= 0; i--) if (pauses[i] != 0) { pauses[i] = SpeechSegmenter.PARAGRAPH; break; }
                    }
                    float[] audio=VitsMnn.generate(labels,pauses,speaker,rate);
                    if (audio==null || audio.length==0) throw new IOException("未生成有效语音");
                    samples+=audio.length; if(samples>22050L*900) throw new IOException("播报超过15分钟");
                    ByteBuffer pcm=ByteBuffer.allocate(8192).order(ByteOrder.LITTLE_ENDIAN);
                    for(float value:audio) {
                        if(!Float.isFinite(value)) throw new IOException("无效的音频采样");
                        peak=Math.max(peak,Math.abs(value));
                        pcm.putShort((short)Math.round(Math.max(-1,Math.min(1,value))*32767));
                        if(!pcm.hasRemaining()) { output.write(pcm.array()); pcm.clear(); }
                    }
                    if(pcm.position()>0) output.write(pcm.array(),0,pcm.position());
                }
            }
            if(samples==0 || peak<0.0001) throw new IOException("没有生成有效的朗读声音");
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
