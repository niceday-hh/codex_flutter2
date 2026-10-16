package com.niceday.memo;

import android.content.Context;
import java.io.*;
import java.util.Properties;

/** Stream large assets off the platform thread, retaining a validated cache. */
public final class AsrAssets {
    private AsrAssets() {}
    public static synchronized String prepare(Context context) throws IOException {
        return prepare(new File(context.getFilesDir(), "asr"), name -> context.getAssets().open("flutter_assets/assets/models/" + name));
    }
    interface Source { InputStream open(String name) throws IOException; }
    static String prepare(File dir, Source source) throws IOException {
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("无法创建语音模型目录");
        File marker = new File(dir, "cache-v1.properties");
        Properties previous = new Properties();
        if (marker.isFile()) try (InputStream in = new FileInputStream(marker)) { previous.load(in); }
        Properties sizes = new Properties();
        for (String name : new String[]{"model.int8.onnx", "tokens.txt"}) {
            File target = new File(dir, name);
            String expected = previous.getProperty(name, "0");
            if (target.isFile() && target.length() > 0 && expected.equals(Long.toString(target.length()))) {
                sizes.setProperty(name, expected); continue;
            }
            File temp = new File(dir, name + ".tmp");
            try {
                try (InputStream input = source.open(name);
                     FileOutputStream output = new FileOutputStream(temp)) {
                    byte[] buffer = new byte[65536]; int count;
                    while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                    output.getFD().sync();
                }
                if (temp.length() == 0) throw new IOException("语音模型为空，请重新安装完整安装包");
                if (!temp.renameTo(target)) throw new IOException("无法保存语音模型");
                sizes.setProperty(name, Long.toString(target.length()));
            } finally { if (temp.exists()) temp.delete(); }
        }
        File temp = new File(dir, "cache-v1.tmp");
        try (FileOutputStream output = new FileOutputStream(temp)) { sizes.store(output, "paraformer-zh-int8-v1"); output.getFD().sync(); }
        if (!temp.renameTo(marker)) throw new IOException("无法保存语音缓存状态");
        return dir.getAbsolutePath();
    }
}
