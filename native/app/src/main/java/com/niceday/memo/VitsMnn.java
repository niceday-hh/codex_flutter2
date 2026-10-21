package com.niceday.memo;

/** CPU-only JNI; callers serialize batches and release the model after synthesis. */
final class VitsMnn {
    static { System.loadLibrary("memo_vits"); }
    static native void open(String directory);
    static float[] generate(int[] labels, int[] pauses, int speaker, float speed) {
        return generateProfile(labels, pauses, speaker, speed, false, true);
    }
    static float[] generateProfile(int[] labels, int[] pauses, int speaker, float speed, boolean legacy, boolean boundedPauses) {
        return generateWithOptions(labels, pauses, speaker, speed, legacy, boundedPauses, .6f, .668f, 1);
    }
    static native float[] generateWithOptions(int[] labels, int[] pauses, int speaker, float speed, boolean legacy,
        boolean boundedPauses, float noise, float noiseW, long seed);
    static native float[] lastDurations();
    static native void close();
}
