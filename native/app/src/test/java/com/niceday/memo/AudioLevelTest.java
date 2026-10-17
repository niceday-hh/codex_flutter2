package com.niceday.memo;
import org.junit.Test;
import static org.junit.Assert.*;

public class AudioLevelTest {
    @Test public void silenceAndInvalidCountsStayAtFloor() {
        assertEquals(-90,AudioLevel.dbfs(0,1600),0);
        assertEquals(-90,AudioLevel.dbfs(123,0),0);
    }
    @Test public void measuredPcmEnergyMatchesDbfsAndCannotOverflowShortSamples() {
        assertEquals(-6.0206,AudioLevel.dbfs(1600L*16384*16384,1600),0.001);
        assertEquals(0,AudioLevel.dbfs(1600L*32768*32768,1600),0.001);
        assertTrue(AudioLevel.dbfs(1600L*1024*1024,1600)<AudioLevel.dbfs(1600L*8192*8192,1600));
    }
}
