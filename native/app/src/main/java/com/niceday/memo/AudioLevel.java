package com.niceday.memo;

/** Digital amplitude only, not an environmental sound-pressure measurement. */
public final class AudioLevel {
    private AudioLevel() {}
    public static double dbfs(long sumSquares, int count) {
        if(count<=0 || sumSquares<=0) return -90;
        return Math.max(-90, Math.min(0, 10*Math.log10((double)sumSquares/count/(32768.0*32768.0))));
    }
}
