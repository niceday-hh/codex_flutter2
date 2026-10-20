package com.niceday.memo.tts;

import java.text.BreakIterator;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** Keep sentence context; split long sentences at punctuation before using word boundaries. */
public final class SpeechSegmenter {
    public static final int CONTINUATION = 0, LIST = 1, CLAUSE = 2, SENTENCE = 3, PARAGRAPH = 4;
    public static final int MAX_CODE_POINTS = 48;
    public static final class Segment {
        public final String text;
        public final int boundary;
        public Segment(String text, int boundary) { this.text = text; this.boundary = boundary; }
        public boolean terminal() { return boundary >= SENTENCE; }
    }
    private SpeechSegmenter() {}
    public static int punctuation(int cp) {
        if (cp == '、') return LIST;
        if (cp == ',' || cp == '，' || cp == ';' || cp == '；' || cp == ':' || cp == '：') return CLAUSE;
        if (cp == '.' || cp == '。' || cp == '!' || cp == '！' || cp == '?' || cp == '？' || cp == '…') return SENTENCE;
        return 0;
    }
    public static List<Segment> split(String text) { return split(text, MAX_CODE_POINTS); }
    public static List<Segment> split(String text, int limit) {
        if (limit < 1) throw new IllegalArgumentException("Invalid segment limit");
        List<Segment> out = new ArrayList<>();
        // Paragraph boundaries are retained before the normalizer turns newlines into punctuation.
        String[] paragraphs = text.replace("\r\n", "\n").replace('\r', '\n').split("\n", -1);
        for (String paragraph : paragraphs) {
            int start = 0;
            while (start < paragraph.length()) {
                int end = paragraph.offsetByCodePoints(start, Math.min(limit, paragraph.codePointCount(start, paragraph.length())));
                int sentence = -1, clause = -1;
                for (int p = start; p < end;) {
                    int cp = paragraph.codePointAt(p), next = p + Character.charCount(cp);
                    int kind = punctuation(cp);
                    // A decimal point/clock separator inside a number is not a sentence boundary.
                    boolean numeric = p > 0 && next < paragraph.length() && Character.isDigit(paragraph.codePointBefore(p)) && Character.isDigit(paragraph.codePointAt(next));
                    if (!numeric && kind >= SENTENCE) sentence = next;
                    else if (!numeric && kind > 0) clause = next;
                    p = next;
                }
                if (end < paragraph.length()) {
                    if (sentence > start) end = sentence;
                    else if (clause > start) end = clause;
                    else {
                        BreakIterator words = BreakIterator.getWordInstance(Locale.CHINA);
                        words.setText(paragraph);
                        int word = words.isBoundary(end) ? end : words.preceding(end);
                        if (word > start) end = word;
                        // Keep a numeric run intact whenever it fits in the remaining text.
                        if (end < paragraph.length() && Character.isDigit(paragraph.codePointBefore(end)) && Character.isDigit(paragraph.codePointAt(end))) {
                            int p = end;
                            while (p > start && Character.isDigit(paragraph.codePointBefore(p))) p -= Character.charCount(paragraph.codePointBefore(p));
                            if (p > start) end = p;
                        }
                    }
                }
                String part = paragraph.substring(start, end);
                int boundary = end == paragraph.length() ? PARAGRAPH : punctuation(part.codePointBefore(part.length()));
                out.add(new Segment(part, boundary)); start = end;
            }
        }
        return out;
    }
}
