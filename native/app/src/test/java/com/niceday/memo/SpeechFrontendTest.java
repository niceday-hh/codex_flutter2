package com.niceday.memo;

import com.niceday.memo.tts.ChineseCleaners;
import com.niceday.memo.tts.ChineseTextUtils;
import com.niceday.memo.tts.PreparedText;
import com.niceday.memo.tts.Normalizer;
import java.util.Arrays;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class SpeechFrontendTest {
    private ChineseTextUtils frontend() {
        return new ChineseTextUtils(Arrays.asList("_", ",", ".", "!", "?", "-", "~", "…", "A", "E", "I", "N", "O", "Q", "U", "a", "b", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "r", "s", "t", "u", "v", "w", "y", "z", "ʃ", "ʧ", "ʦ", "ɯ", "ɹ", "ə", "ɥ", "⁼", "ʰ", "`", "→", "↓", "↑", " "), "chinese_cleaners", RuntimeEnvironment.getApplication().getAssets());
    }
    @Test public void internalSplitDoesNotInventAFinalPeriod() {
        ChineseCleaners cleaner = new ChineseCleaners();
        assertFalse(cleaner.chinese_clean_text1("重新开始录音", false, true).endsWith("."));
        assertTrue(cleaner.chinese_clean_text1("重新开始录音", true, true).endsWith("."));
    }
    @Test public void enumerationAndCommaShareTrainedSymbolButKeepDifferentPauseMetadata() {
        PreparedText p = frontend().encode("喝水、休息，再出发。", true);
        assertEquals(p.getLabels().length, p.getPauses().length);
        int list = 0, clause = 0, sentence = 0;
        for (int i = 0; i < p.getLabels().length; i++) {
            int kind = p.getPauses()[i];
            if (kind == 1) { list++; assertEquals(1, p.getLabels()[i]); }
            if (kind == 2) { clause++; assertEquals(1, p.getLabels()[i]); }
            if (kind == 3) { sentence++; assertEquals(2, p.getLabels()[i]); }
            if (p.getLabels()[i] == 0 || p.getLabels()[i] == 51) assertEquals(0, kind);
        }
        assertEquals(1, list); assertEquals(1, clause); assertEquals(1, sentence);
    }
    @Test public void correctedApicalSyllablesDoNotHaveSpaceBeforeTheTone() {
        String phones = new ChineseCleaners().chinese_clean_text1("知识支持自己吃饭日子", false, true);
        assertFalse(phones.matches(".*[ʦsɹ]`?[⁼ʰ]? +[→↓↑].*"));
        assertTrue(phones.contains("ɹ"));
    }
    @Test public void reminderTimeIsNormalizedBeforePhonemeLengthChecking() {
        assertEquals("八点零五分喝水、休息", new Normalizer().normalizeText("8:05喝水、休息", "!?…,.'、-", true));
        assertTrue(frontend().encode("8:05喝水", true).getLabels().length > 3);
    }
    @Test public void quotationMarksDoNotShiftCommaOrSentenceMetadata() {
        PreparedText p = frontend().encode("小李问：“今天出发吗？”老王说：“别急，先休息。”", true);
        assertArrayEquals(new int[]{2,3,2,2,3}, Arrays.stream(p.getPauses()).filter(k -> k != 0).toArray());
    }

    @Test public void latinLettersAreRetainedForChineseLetterNames() {
        assertEquals("APP提醒", new Normalizer().normalizeText("APP提醒", "!?…,.'、-", true));
        assertTrue(frontend().encode("APP", true).getLabels().length > 3);
    }
    @Test public void jiebaKeepsCommonPhraseBoundaries() {
        assertEquals(Arrays.asList("城市", "刚刚", "醒来"),
            new com.huaban.analysis.jieba.JiebaSegmenter().sentenceProcess("城市刚刚醒来"));
    }

}
