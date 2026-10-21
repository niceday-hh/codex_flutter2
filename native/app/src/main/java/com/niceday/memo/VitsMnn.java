package com.niceday.memo;

/** CPU-only JNI; callers serialize batches and release the model after synthesis. */
final class VitsMnn {
    static { System.loadLibrary("memo_vits"); }
    static native void open(String directory);
    static float[] generate(int[] labels, int[] pauses, int speaker, float speed) {
        return generateProfile(labels, pauses, speaker, speed, false, true);
    }
    static native float[] generateProfile(int[] labels, int[] pauses, int speaker, float speed, boolean legacy, boolean boundedPauses);
    static native float[] lastDurations();
    static native void close();
}
