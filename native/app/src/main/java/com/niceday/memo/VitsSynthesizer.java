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
    int lastSegmentCount;
    JSONArray audit; // Only populated by the debug synthesis audit.
    void open(Context c, String directory) throws Exception {
        JSONObject config = new JSONObject(new String(java.nio.file.Files.readAllBytes(new File(directory, "config.json").toPath()), StandardCharsets.UTF_8));
        if (config.getJSONArray("speakers").length() != 804 || config.getJSONObject("data").getInt("sampling_rate") != 22050)
            throw new IOException("播报模型元信息不匹配");
        List<String> symbols = new ArrayList<>(); JSONArray values = config.getJSONArray("symbols");
        for (int i=0;i<values.length();i++) symbols.add(values.getString(i));
        if (symbols.size() <= 51 || !"_".equals(symbols.get(0)) || !" ".equals(symbols.get(51)))
            throw new IOException("播报模型符号表与停顿策略不匹配");
        cleaner = new ChineseTextUtils(symbols, "chinese_cleaners", c.getAssets()); cleaner.initPinyinEngine();
        VitsMnn.open(directory); opened=true;
    }
    void generate(Context c, JSONObject job) throws Exception {
        String key = job.getString("key"), text = job.getString("text");
        if (cleaner == null || !SpeechCache.pending(key)) throw new IllegalArgumentException("语音任务已失效");
        int speaker = job.getInt("sid"); float rate = (float)job.getDouble("rate");
        File temporary = new File(SpeechCache.directory(c), key+".part");
        render(text, speaker, rate, temporary, 5, (float)job.optDouble("noise", .6), (float)job.optDouble("noiseW", .668), job.optLong("seed", 1));
    }
    /** Diagnostic stages are called only by the debug-only audit Activity. */
    void render(String text, int speaker, float rate, File temporary, int stage) throws Exception {
        render(text, speaker, rate, temporary, stage, .6f, .668f, 1);
    }
    void render(String text, int speaker, float rate, File temporary, int stage, float noise, float noiseW, long seed) throws Exception {
        lastSegmentCount = 0;
        if (cleaner == null || stage < 0 || stage > 5) throw new IllegalArgumentException("Invalid synthesis stage");
        try (RandomAccessFile output = new RandomAccessFile(temporary,"rw")) {
            output.setLength(0); output.write(new byte[44]); long samples=0; double peak=0;
            ArrayDeque<SpeechSegmenter.Segment> chunks = new ArrayDeque<>(SpeechSegmenter.split(text));
            if (stage == 0) {
                chunks.clear();
                for (int start = 0; start < text.length();) {
                    int end = text.offsetByCodePoints(start, Math.min(24, text.codePointCount(start, text.length())));
                    chunks.add(new SpeechSegmenter.Segment(text.substring(start, end), SpeechSegmenter.SENTENCE)); start = end;
                }
            }
            while (!chunks.isEmpty()) {
                SpeechSegmenter.Segment segment = chunks.removeFirst();
                PreparedText prepared = cleaner.encode(segment.text, stage == 0 || segment.terminal(), stage >= 2);
                int[] labels = prepared.getLabels(), pauses = prepared.getPauses();
                if (labels.length > 960) {
                    int count = segment.text.codePointCount(0, segment.text.length());
                    if (count <= 1) throw new IOException("单个文本单元超过合成上限");
                    List<SpeechSegmenter.Segment> smaller = SpeechSegmenter.split(segment.text, Math.max(1, count / 2));
                    for (int i = smaller.size() - 1; i >= 0; i--) {
                        SpeechSegmenter.Segment child = smaller.get(i);
                        int boundary = i == smaller.size() - 1 ? segment.boundary : SpeechSegmenter.trailingBoundary(child.text);
                        chunks.addFirst(new SpeechSegmenter.Segment(child.text, boundary));
                    }
                    continue;
                }
                {
                    if (labels.length < 3) continue;
                    if (segment.boundary == SpeechSegmenter.PARAGRAPH) {
                        for (int i = pauses.length - 1; i >= 0; i--) if (pauses[i] != 0) { pauses[i] = SpeechSegmenter.PARAGRAPH; break; }
                    }
                    // Web baseline: leave learned durations unchanged, including punctuation.
                    if (stage < 3) Arrays.fill(pauses, 0);
                    int[] inferencePauses = stage == 5 ? new int[pauses.length] : pauses;
                    long chunkSeed = (seed + 0x9E3779B9L * lastSegmentCount) & 0xffffffffL;
                    float[] audio=VitsMnn.generateWithOptions(labels,inferencePauses,speaker,rate,stage < 2,stage == 4,noise,noiseW,chunkSeed);
                    lastSegmentCount++;
                    if (audio==null || audio.length==0) throw new IOException("未生成有效语音");
                    if (audit != null) tracePauses(labels, pauses, VitsMnn.lastDurations(), samples, segment.text);
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
    private void tracePauses(int[] ids, int[] kinds, float[] frames, long offset, String text) throws JSONException {
        double[] prefix = new double[frames.length + 1];
        for (int i = 0; i < frames.length; i++) prefix[i + 1] = prefix[i] + frames[i];
        for (int p = 0; p < ids.length;) {
            if (kinds[p] == 0) { p++; continue; }
            int first = p, last = p, kind = kinds[p];
            while (first > 0 && (ids[first - 1] == 0 || ids[first - 1] == 51)) first--;
            while (last + 1 < ids.length && (ids[last + 1] == 0 || ids[last + 1] == 51 || kinds[last + 1] != 0)) {
                last++; kind = Math.max(kind, kinds[last]);
            }
            audit.put(new JSONObject().put("kind", kind).put("text", text)
                .put("start", (offset + prefix[first] * 256) / 22050.)
                .put("seconds", (prefix[last + 1] - prefix[first]) * 256 / 22050.));
            p = last + 1;
        }
    }
    void close() { cleaner=null; if(opened) { opened=false; VitsMnn.close(); } }
}
