package com.niceday.memo;

import com.niceday.memo.tts.SpeechSegmenter;
import java.util.List;
import org.junit.Test;
import static org.junit.Assert.*;

public class SpeechSegmenterTest {
    static final String PARAGRAPH = "关于这个超级提醒APP，目前还有几点需要优化：\n首先第一点就是每次从其他地方进入到界面里都会切到首页并开始录音，这个是可以的，但是在进入界面之后切换到不同tab页，再切回主页tab，它还是会重新开始录音这一部分，其实可以省略的，防止它反复的开始录音、停止录音，造成不必要的开销。其实可以只保留从外部软件或者是桌面切换到该APP时才重新开始准备预听语音指令。";
    @Test public void suppliedParagraphKeepsWordsAndTextAtPunctuationBoundaries() {
        List<SpeechSegmenter.Segment> parts = SpeechSegmenter.split(PARAGRAPH);
        StringBuilder joined = new StringBuilder();
        for (SpeechSegmenter.Segment part : parts) {
            joined.append(part.text);
            assertTrue(part.text.codePointCount(0, part.text.length()) <= SpeechSegmenter.MAX_CODE_POINTS);
            assertFalse(part.text.endsWith("重")); assertFalse(part.text.endsWith("开"));
            assertTrue(part.boundary > 0);
        }
        assertEquals(PARAGRAPH.replace("\n", ""), joined.toString());
        assertTrue(parts.size() < 8);
    }
    @Test public void shortSentenceKeepsCommaContext() {
        List<SpeechSegmenter.Segment> parts = SpeechSegmenter.split("喝水、休息眼睛，然后准备出门。");
        assertEquals(1, parts.size()); assertTrue(parts.get(0).terminal());
    }
    @Test public void unpunctuatedFallbackIsBoundedAndDoesNotInventSentenceEnds() {
        String text = "请记得带好今天需要使用的物品并在出门前再次核对所有重要事项".repeat(20);
        StringBuilder joined = new StringBuilder(); List<SpeechSegmenter.Segment> parts = SpeechSegmenter.split(text);
        for (int i = 0; i < parts.size(); i++) {
            var part = parts.get(i); joined.append(part.text);
            assertTrue(part.text.codePointCount(0, part.text.length()) <= 48);
            if (i + 1 < parts.size()) assertFalse(part.terminal());
        }
        assertEquals(text, joined.toString());
    }
    @Test public void supplementaryCharactersAndEmptyParagraphsMakeProgress() {
        String text = "提醒😀".repeat(35);
        assertEquals(text, SpeechSegmenter.split("\n\n" + text).stream().map(s -> s.text).reduce("", String::concat));
        assertTrue(SpeechSegmenter.split("").isEmpty());
        assertEquals(SpeechSegmenter.LIST, SpeechSegmenter.punctuation('、'));
    }
    @Test public void forcedFallbackKeepsClockDateDecimalAndUnitsTogether() {
        for (String unit : new String[]{"8:05", "2026年10月20日", "12.5%", "100毫升", "APP"}) {
            String text = "请记得核对".repeat(8) + unit + "以后再继续处理其他事项";
            int limit = 50;
            var parts = SpeechSegmenter.split(text, limit);
            assertEquals(text, parts.stream().map(s -> s.text).reduce("", String::concat));
            assertTrue(unit, parts.stream().anyMatch(s -> s.text.contains(unit)));
        }
    }
}
