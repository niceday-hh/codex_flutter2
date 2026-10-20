// Adapted from Voine/VITS-MNN (Apache-2.0); see docs/third-party-vits.md.
package com.niceday.memo.tts

import android.content.res.AssetManager
import com.github.houbb.pinyin.constant.enums.PinyinStyleEnum
import com.github.houbb.pinyin.util.PinyinHelper
import java.util.ArrayDeque

data class PreparedText(val labels: IntArray, val pauses: IntArray)

class ChineseTextUtils(
    override val symbols: List<String>,
    override val cleanerName: String,
    override val assetManager: AssetManager
) : TextUtils {
    private val punctuation = "!?…,.'、-"
    private val normalizer = Normalizer()
    private val symbolToIndex = symbols.withIndex().associate { it.value to it.index }
    override fun cleanInputs(text: String): String = normalizer.normalizeText(text, punctuation, true)
    override fun initPinyinEngine() { PinyinHelper.toPinyin("你好", PinyinStyleEnum.NUM_LAST) }
    override fun splitSentence(text: String): List<String> = text.split("\n").filter { it.isNotEmpty() }

    @JvmOverloads
    fun encode(text: String, terminal: Boolean, corrected: Boolean = true): PreparedText {
        require(cleanerName == "chinese_cleaners" || cleanerName == "chinese_cleaners1")
        val input = normalizer.normalizeText(text, punctuation, corrected)
        val boundaries = ArrayDeque<Int>()
        input.codePoints().forEach { cp ->
            val kind = SpeechSegmenter.punctuation(cp)
            if (kind > 0) boundaries.add(kind)
        }
        val phonemes = ChineseCleaners().chinese_clean_text1(input, terminal, corrected)
        val labels = arrayListOf(0)
        val pauses = arrayListOf(0)
        for (symbol in phonemes) {
            val id = symbolToIndex[symbol.toString()] ?: continue
            val isPause = SpeechSegmenter.punctuation(symbol.code) > 0
            val kind = if (isPause) {
                if (boundaries.isEmpty()) SpeechSegmenter.SENTENCE else boundaries.removeFirst()
            } else 0
            labels.add(id); labels.add(0)
            pauses.add(kind); pauses.add(0)
        }
        return PreparedText(labels.toIntArray(), pauses.toIntArray())
    }
    override fun wordsToLabels(text: String): IntArray = encode(text, true).labels
    override fun convertSentenceToLabels(text: String): List<IntArray> = splitSentence(text).map { wordsToLabels(it) }
    override fun convertText(text: String): List<IntArray> = convertSentenceToLabels(text)
}
