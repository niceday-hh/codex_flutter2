// Adapted from Voine/VITS-MNN (Apache-2.0); see docs/third-party-vits.md.
package com.niceday.memo.tts

import kotlin.collections.getOrNull
import kotlin.collections.iterator
import kotlin.collections.joinToString
import kotlin.text.contains
import kotlin.text.digitToInt
import kotlin.text.dropLast
import kotlin.text.map
import kotlin.text.mapIndexed
import kotlin.text.orEmpty
import kotlin.text.replace
import kotlin.text.split
import kotlin.to

/**
 * Author: Voine
 * Date: 2025/4/17
 * Description: simple ver for normalizer: cn2an.transform(x, "an2cn")
 */
class Normalizer {

    private fun normalizeNumberText(text: String): String {
        return text
            .replace(Regex("""(\d{1,2}):(\d{2})(?::(\d{2}))?""")) {
                val h = it.groupValues[1].toInt()
                val m = it.groupValues[2].toInt()
                if (h > 23 || m > 59) it.value else arabicToChinese(h.toString()) + "点" +
                    (if (m == 0) "整" else (if (m < 10) "零" else "") + arabicToChinese(m.toString()) + "分") +
                    (if (it.groupValues[3].isEmpty()) "" else arabicToChinese(it.groupValues[3]) + "秒")
            }
            .replace(Regex("""(\d{2,4})年(\d{1,2})月(\d{1,2})日""")) {
                val (y, m, d) = it.destructured
                y.map { "零一二三四五六七八九"[it.digitToInt()] }.joinToString("") + "年" + arabicToChinese(m) + "月" + arabicToChinese(d) + "日"
            }
            .replace(Regex("""(\d{1,4})月(\d{1,2})日""")) {
                val (m, d) = it.destructured
                arabicToChinese(m) + "月" + arabicToChinese(d) + "日"
            }
            .replace(Regex("""(\d{1,2})日""")) {
                arabicToChinese(it.value.dropLast(1)) + "日"
            }
            .replace(Regex("""\d+/\d+""")) {
                val (a, b) = it.value.split("/")
                arabicToChinese(b) + "分之" + arabicToChinese(a)
            }
            .replace(Regex("""-?(\d+\.)?\d+%""")) {
                "百分之" + arabicToChinese(it.value.dropLast(1))
            }
            .replace(Regex("""\d+℃""")) {
                arabicToChinese(it.value.dropLast(1)) + "摄氏度"
            }
            .replace(Regex("""-?(\d+\.)?\d+""")) {
                arabicToChinese(it.value)
            }
    }

    private fun arabicToChinese(numStr: String): String {
        val digits = "零一二三四五六七八九"
        val negative = numStr.startsWith("-")
        val parts = numStr.removePrefix("-").split(".")
        if (parts.any { p -> p.isEmpty() || p.any { !it.isDigit() } }) return numStr
        fun small(number: Int): String {
            if (number == 0) return "零"
            val units = listOf("千", "百", "十", "")
            val divisors = listOf(1000, 100, 10, 1)
            val result = StringBuilder(); var zero = false
            for (i in divisors.indices) {
                val digit = number / divisors[i] % 10
                if (digit == 0) { if (result.isNotEmpty()) zero = true }
                else {
                    if (zero) result.append('零')
                    if (!(digit == 1 && i == 2 && result.isEmpty())) result.append(digits[digit])
                    result.append(units[i]); zero = false
                }
            }
            return result.toString()
        }
        val raw = parts[0]
        val value = raw.toLongOrNull()
        val integer = when {
            value == null || raw.length > 8 || (raw.length > 1 && raw.startsWith("0")) -> raw.map { digits[it.digitToInt()] }.joinToString("")
            value < 10000 -> small(value.toInt())
            else -> small((value / 10000).toInt()) + "万" + (if (value % 10000 == 0L) "" else (if (value % 10000 < 1000) "零" else "") + small((value % 10000).toInt()))
        }
        return (if (negative) "负" else "") + integer + (if (parts.size < 2) "" else "点" + parts[1].map { digits[it.digitToInt()] }.joinToString(""))
    }

    @JvmOverloads
    fun normalizeText(text: String, punctuation: String, preserveListPause: Boolean = false): String {
        val repMap = mapOf(
            "：" to ",", "；" to ",", "，" to ",", "。" to ".", "！" to "!", "？" to "?",
            "\n" to ".", "·" to ",", "、" to if (preserveListPause) "、" else ",", "..." to "…", "$" to ".",
            "“" to "'", "”" to "'", "\"" to "'", "‘" to "'", "’" to "'",
            "（" to "'", "）" to "'", "(" to "'", ")" to "'",
            "《" to "'", "》" to "'", "【" to "'", "】" to "'", "[" to "'", "]" to "'",
            "—" to "-", "～" to "-", "~" to "-", "「" to "'", "」" to "'"
        )

        var result = text.replace("嗯", "恩").replace("呣", "母")
        result = normalizeNumberText(result)
        for ((k, v) in repMap) {
            result = result.replace(k, v)
        }
        val regex = Regex("[^\u4e00-\u9fa5${punctuation}]+")
        return result.replace(regex, "")
    }
}
