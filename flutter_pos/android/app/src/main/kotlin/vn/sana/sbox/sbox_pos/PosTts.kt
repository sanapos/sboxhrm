package vn.sana.sbox.sbox_pos

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/// Android TTS. Ưu tiên Google Text-to-Speech giọng nữ vi-VN (rõ hơn Pico/máy mặc định).
/// T1 (API 23) không dùng flutter_tts.
object PosTts {
    const val CHANNEL = "com.sboxhrm/tts"
    private const val GOOGLE = "com.google.android.tts"

    private var tts: TextToSpeech? = null
    private var ready = false
    private var pending: String? = null
    private var binding = false
    private var preferredVoice: String? = null
    private var speechRate = 0.78f
    private var pendingList: MethodChannel.Result? = null

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "speak" -> {
                call.argument<String>("voice")?.let { preferredVoice = it }
                call.argument<Double>("rate")?.let { speechRate = it.toFloat() }
                speak(context, call.argument<String>("text") ?: "")
                result.success(true)
            }
            "stop" -> {
                tts?.stop()
                result.success(true)
            }
            "setOptions" -> {
                call.argument<String>("voice")?.let { preferredVoice = it }
                call.argument<Double>("rate")?.let { speechRate = it.toFloat() }
                if (ready) applyVoiceAndRate()
                result.success(true)
            }
            "listVoices" -> {
                if (ready) {
                    result.success(voiceMaps())
                } else {
                    pendingList = result
                    if (tts == null && !binding) {
                        bind(context, preferGoogle = hasPackage(context, GOOGLE))
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun shutdown() {
        pending = null
        pendingList = null
        ready = false
        binding = false
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
    }

    private fun speak(context: Context, text: String) {
        if (text.isBlank()) return
        pending = text
        if (tts == null && !binding) {
            bind(context, preferGoogle = hasPackage(context, GOOGLE))
            return
        }
        if (ready) flushPending()
    }

    private fun hasPackage(context: Context, pkg: String): Boolean {
        return try {
            context.packageManager.getPackageInfo(pkg, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun bind(context: Context, preferGoogle: Boolean) {
        binding = true
        val app = context.applicationContext
        val listener = TextToSpeech.OnInitListener { status ->
            if (status != TextToSpeech.SUCCESS) {
                try {
                    tts?.shutdown()
                } catch (_: Exception) {
                }
                tts = null
                binding = false
                if (preferGoogle) {
                    bind(context, preferGoogle = false)
                    return@OnInitListener
                }
                ready = false
                pendingList?.error("tts", "init failed", null)
                pendingList = null
                return@OnInitListener
            }
            applyVoiceAndRate()
            ready = true
            binding = false
            pendingList?.success(voiceMaps())
            pendingList = null
            flushPending()
        }
        tts = if (preferGoogle) {
            TextToSpeech(app, listener, GOOGLE)
        } else {
            TextToSpeech(app, listener)
        }
    }

    private fun applyVoiceAndRate() {
        val engine = tts ?: return
        val vi = Locale("vi", "VN")
        val lang = engine.setLanguage(vi)
        if (lang == TextToSpeech.LANG_MISSING_DATA ||
            lang == TextToSpeech.LANG_NOT_SUPPORTED
        ) {
            engine.language = Locale("vi")
        }
        engine.setSpeechRate(speechRate)
        engine.setPitch(1.05f)
        if (Build.VERSION.SDK_INT < 21) return
        val voices = try {
            engine.voices
        } catch (_: Exception) {
            null
        } ?: return
        val chosen = preferredVoice?.let { want ->
            voices.firstOrNull { it.name == want }
        } ?: voices.maxByOrNull { scoreVoice(it) }
        if (chosen != null && scoreVoice(chosen) > 0) {
            try {
                engine.voice = chosen
            } catch (_: Exception) {
            }
        }
    }

    private fun voiceMaps(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < 21) return emptyList()
        val engine = tts ?: return emptyList()
        val voices = try {
            engine.voices
        } catch (_: Exception) {
            null
        } ?: return emptyList()
        return voices.mapNotNull { v ->
            val s = scoreVoice(v)
            if (s < 0) return@mapNotNull null
            val loc = v.locale?.toString() ?: "vi-VN"
            mapOf(
                "name" to v.name,
                "locale" to loc,
                "label" to labelVoice(v),
                "score" to s,
            )
        }
    }

    private fun labelVoice(v: Voice): String {
        val n = v.name.lowercase(Locale.US)
        val tags = ArrayList<String>()
        if (n.contains("wavenet") || n.contains("neural") || n.contains("natural")) {
            tags.add("Mượt")
        } else if (v.isNetworkConnectionRequired) {
            tags.add("Mạng")
        } else {
            tags.add("Máy")
        }
        if (n.contains("female") || n.contains("vif")) tags.add("Nữ")
        else if (n.contains("male") || n.contains("vid")) tags.add("Nam")
        var short = v.name
            .replace(Regex("com\\.google\\.android\\.tts[.:]?", RegexOption.IGNORE_CASE), "")
            .replace(Regex("vi[-_]?vn[-_.]?", RegexOption.IGNORE_CASE), "")
        if (short.length > 22) short = short.substring(0, 22)
        if (short.isBlank()) short = v.locale?.toString() ?: "vi"
        return tags.joinToString(" · ") + " · " + short
    }

    private fun scoreVoice(v: Voice): Int {
        val loc = v.locale ?: return -100
        if (!loc.language.equals("vi", ignoreCase = true)) return -100
        val n = v.name.lowercase(Locale.US)
        var s = 10
        if (n.contains("wavenet") || n.contains("neural") || n.contains("natural")) s += 12
        if (n.contains("vif") || n.contains("female")) s += 8
        if (!v.isNetworkConnectionRequired) s += 4
        if (n.contains("local")) s += 2
        if (n.contains("vid") || n.contains("male")) s -= 3
        s += v.quality / 200
        return s
    }

    private fun flushPending() {
        val text = pending ?: return
        pending = null
        val engine = tts ?: return
        applyVoiceAndRate()
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "kds-vi")
    }
}
