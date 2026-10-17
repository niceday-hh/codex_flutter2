package com.niceday.memo;

/** CPU-only JNI; callers serialize batches and release the model after synthesis. */
final class VitsMnn {
    static { System.loadLibrary("memo_vits"); }
    static native void open(String directory);
    static native float[] generate(int[] labels, int speaker, float speed);
    static native void close();
}
