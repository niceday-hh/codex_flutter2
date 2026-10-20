package com.niceday.memo;

/** CPU-only JNI; callers serialize batches and release the model after synthesis. */
final class VitsMnn {
    static { System.loadLibrary("memo_vits"); }
    static native void open(String directory);
    static float[] generate(int[] labels, int[] pauses, int speaker, float speed) {
        return generateProfile(labels, pauses, speaker, speed, false);
    }
    static native float[] generateProfile(int[] labels, int[] pauses, int speaker, float speed, boolean legacy);
    static native void close();
}
