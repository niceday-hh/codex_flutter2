package com.niceday.memo;

import android.content.Context;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

/** Copies and verifies the small TTS resources outside the UI thread. */
final class TtsAssets {
    static synchronized String prepare(Context context) throws Exception {
        String prefix = "flutter_assets/assets/tts/";
        JSONObject manifest;
        try (InputStream input = context.getAssets().open(prefix + "manifest.json")) {
            ByteArrayOutputStream content = new ByteArrayOutputStream(); byte[] buffer = new byte[65536]; int n;
            while ((n = input.read(buffer)) != -1) content.write(buffer, 0, n);
            manifest = new JSONObject(content.toString("UTF-8"));
        }
        File dir = new File(context.getFilesDir(), "tts-aishell3-v1");
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("无法建立播报模型目录");
        JSONObject files = manifest.getJSONObject("files");
        for (java.util.Iterator<String> keys = files.keys(); keys.hasNext();) {
            String name = keys.next();
            if (!name.matches("[a-zA-Z0-9_.-]+")) throw new IOException("模型资源名称无效");
            JSONObject entry = files.getJSONObject(name);
            File target = new File(dir, name), marker = new File(dir, name + ".sha256");
            String hash = entry.getString("sha256");
            if (target.isFile() && target.length() == entry.getLong("bytes") && marker.isFile() &&
                new String(java.nio.file.Files.readAllBytes(marker.toPath()), StandardCharsets.UTF_8).equals(hash)) continue;
            File temporary = new File(dir, name + ".tmp");
            try {
                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                try (InputStream input = context.getAssets().open(prefix + name); FileOutputStream output = new FileOutputStream(temporary)) {
                    byte[] buffer = new byte[65536]; int n;
                    while ((n = input.read(buffer)) != -1) { output.write(buffer, 0, n); digest.update(buffer, 0, n); }
                    output.getFD().sync();
                }
                StringBuilder actual = new StringBuilder();
                for (byte b : digest.digest()) actual.append(String.format(Locale.ROOT, "%02x", b & 255));
                if (temporary.length() != entry.getLong("bytes") || !actual.toString().equals(hash) || !temporary.renameTo(target))
                    throw new IOException("播报模型校验失败");
                java.nio.file.Files.write(marker.toPath(), hash.getBytes(StandardCharsets.UTF_8));
            } finally { temporary.delete(); }
        }
        return dir.getPath();
    }
}
