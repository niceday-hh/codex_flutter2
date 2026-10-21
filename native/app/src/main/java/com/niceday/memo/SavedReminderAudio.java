package com.niceday.memo;

import android.content.Context;
import android.net.Uri;
import java.io.*;

/** One-time Storage Access Framework export. Never accepts an arbitrary cache path. */
final class SavedReminderAudio {
    static long copy(InputStream source, OutputStream target) throws IOException {
        byte[] buffer = new byte[16384]; long total = 0; int count;
        while ((count = source.read(buffer)) != -1) {
            target.write(buffer, 0, count); total += count;
        }
        target.flush(); return total;
    }
    static long write(Context context, InputStream source, Uri destination) throws IOException {
        try (InputStream input = source) {
            if (destination == null || !"content".equals(destination.getScheme())) throw new IOException("请选择系统文件位置");
            try (OutputStream output = context.getContentResolver().openOutputStream(destination, "wt")) {
                if (output == null) throw new IOException("无法写入所选位置");
                return copy(input, output);
            }
        }
    }
}
