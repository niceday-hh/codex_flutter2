package com.niceday.memo;
import com.niceday.memo.tts.Normalizer;
import org.junit.Test;
import static org.junit.Assert.*;

public class SpeechTextTest {
    @Test public void reminderNumbersAndTimesRemainReadable() {
        Normalizer n=new Normalizer();
        assertEquals("一百毫升",n.normalizeText("100毫升","!?…,.\u0027-"));
        assertEquals("八点零五分喝水",n.normalizeText("8:05喝水","!?…,.\u0027-"));
        assertEquals("二零二六年十月十七日",n.normalizeText("2026年10月17日","!?…,.\u0027-"));
        assertEquals("百分之十二点五",n.normalizeText("12.5%","!?…,.\u0027-"));
        assertEquals("一万零一",n.normalizeText("10001","!?…,.\u0027-"));
    }
}
