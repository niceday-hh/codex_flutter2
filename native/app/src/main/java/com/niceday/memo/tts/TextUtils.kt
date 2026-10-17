// Adapted from Voine/VITS-MNN (Apache-2.0); see docs/third-party-vits.md.
package com.niceday.memo.tts

import android.content.res.AssetManager

interface TextUtils {

    val symbols: List<String>
    val cleanerName: String
    val assetManager: AssetManager

    fun cleanInputs(text: String): String

    fun initPinyinEngine(){}

    fun splitSentence(text: String): List<String>

    fun wordsToLabels(text: String): IntArray

    fun convertSentenceToLabels(
        text: String,
    ): List<IntArray>

    fun convertText(
        text: String,
    ): List<IntArray>
}