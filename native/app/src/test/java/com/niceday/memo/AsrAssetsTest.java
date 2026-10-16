package com.niceday.memo;

import org.junit.*;
import org.junit.rules.TemporaryFolder;
import java.io.*;
import static org.junit.Assert.*;

public class AsrAssetsTest {
    @Rule public TemporaryFolder temp = new TemporaryFolder();
    @Test public void repeatedPreparationReusesCompleteFilesWithoutReadingAssets() throws Exception {
        File dir = temp.newFolder(); final int[] copies = {0};
        AsrAssets.Source source = name -> { copies[0]++; return new ByteArrayInputStream(new byte[]{1, 2, 3}); };
        AsrAssets.prepare(dir, source); assertEquals(2, copies[0]);
        AsrAssets.prepare(dir, name -> { throw new IOException("must reuse cached file"); });
        assertEquals(3, new File(dir, "model.int8.onnx").length());
    }
    @Test public void failedCopyNeverMarksPartialModelReadyAndRetryRecovers() throws Exception {
        File dir = temp.newFolder();
        try { AsrAssets.prepare(dir, name -> new InputStream() { public int read() throws IOException { throw new IOException("interrupted"); } }); fail(); }
        catch (IOException expected) {}
        assertFalse(new File(dir, "cache-v1.properties").exists());
        assertFalse(new File(dir, "model.int8.onnx.tmp").exists());
        AsrAssets.prepare(dir, name -> new ByteArrayInputStream(new byte[]{1, 2, 3}));
        try (FileOutputStream output = new FileOutputStream(new File(dir, "model.int8.onnx"))) { output.write(1); }
        final int[] copied = {0};
        AsrAssets.prepare(dir, name -> { copied[0]++; return new ByteArrayInputStream(new byte[]{4, 5, 6}); });
        assertEquals(1, copied[0]);
    }
}
