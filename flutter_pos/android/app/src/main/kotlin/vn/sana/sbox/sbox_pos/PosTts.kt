package vn.sana.sbox.sbox_pos

import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/// Android TTS. Ưu tiên Google Text-to-Speech giọng nữ vi-VN (rõ hơn Pico/máy mặc định).
/// T1 (API 23) không dùng flutter_tts.
object PosTts {
    const val CHANNEL = "com.sboxhrm/tts"
    private const val TAG = "PosTts"
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
            // Loa ngoài (STREAM_MUSIC) — T1 hay để 0 → KDS đọc / bíp không nghe thấy gì.
            "audioState" -> {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                result.success(
                    mapOf(
                        "music" to am.getStreamVolume(AudioManager.STREAM_MUSIC),
                        "musicMax" to am.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                        "viAvailable" to viAvailable(),
                    )
                )
            }
            "ensureVolume" -> {
                val pct = (call.argument<Int>("percent") ?: 60).coerceIn(10, 100)
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val want = (max * pct + 99) / 100
                val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                if (cur < want) {
                    try {
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, want, 0)
                    } catch (e: Exception) {
                        Log.w(TAG, "setStreamVolume: ${e.message}")
                    }
                }
                result.success(am.getStreamVolume(AudioManager.STREAM_MUSIC))
            }
            "beep" -> {
                playTone()
                result.success(true)
            }
            // «Ting ting» trước khi đọc món mới — Flutter SystemSound.alert không kêu trên Android.
            // Trả về sau khi chuông kêu xong để câu đọc không đè lên tiếng chuông.
            "chime" -> {
                val count = (call.argument<Int>("count") ?: 2).coerceIn(1, 3)
                Thread {
                    val ms = playChime(count)
                    try { Thread.sleep(ms.toLong()) } catch (_: InterruptedException) {}
                    Handler(Looper.getMainLooper()).post { result.success(true) }
                }.start()
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
                // Không có engine TTS → vẫn báo hiệu bằng tiếng bíp.
                if (pending != null) {
                    pending = null
                    playTone()
                }
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
        // Máy không có giọng tiếng Việt (Sunmi T1 thường chỉ có Pico) → đọc sai/câm → bíp.
        val avail = try {
            engine.isLanguageAvailable(Locale("vi", "VN"))
        } catch (_: Exception) {
            TextToSpeech.LANG_NOT_SUPPORTED
        }
        if (avail < TextToSpeech.LANG_AVAILABLE) {
            Log.w(TAG, "vi-VN không có giọng (avail=$avail) → bíp")
            playTone()
            return
        }
        applyVoiceAndRate()
        val r = engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "kds-vi")
        Log.i(TAG, "speak r=$r voice=${try { engine.voice?.name } catch (_: Exception) { null }} text=${text.take(60)}")
    }

    private fun viAvailable(): Boolean? {
        val engine = tts ?: return null
        return try {
            engine.isLanguageAvailable(Locale("vi", "VN")) >= TextToSpeech.LANG_AVAILABLE
        } catch (_: Exception) {
            null
        }
    }

    /// Chuông «ting» tổng hợp (nốt cao + bồi âm, tắt dần) qua STREAM_MUSIC. Trả độ dài (ms).
    private fun playChime(count: Int): Int {
        val rate = 44100
        val noteMs = 260
        val gapMs = 140
        val totalMs = count * noteMs + (count - 1) * gapMs
        val n = rate * totalMs / 1000
        val pcm = ShortArray(n)
        val freqs = doubleArrayOf(1568.0, 2093.0, 1568.0) // G6 → C7 → G6
        for (k in 0 until count) {
            val start = k * (noteMs + gapMs) * rate / 1000
            val len = noteMs * rate / 1000
            val f = freqs[k % freqs.size]
            for (i in 0 until len) {
                val t = i.toDouble() / rate
                val env = Math.exp(-t * 11.0) * minOf(1.0, i / (rate * 0.004))
                val v = Math.sin(2 * Math.PI * f * t) * 0.75 + Math.sin(2 * Math.PI * f * 2.0 * t) * 0.18
                val idx = start + i
                if (idx < n) pcm[idx] = (v * env * 0.9 * Short.MAX_VALUE).toInt().toShort()
            }
        }
        return try {
            val track = AudioTrack(
                AudioManager.STREAM_MUSIC, rate, AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT, n * 2, AudioTrack.MODE_STATIC,
            )
            track.write(pcm, 0, n)
            track.play()
            Handler(Looper.getMainLooper()).postDelayed({
                try { track.release() } catch (_: Exception) {}
            }, totalMs + 400L)
            totalMs + 60
        } catch (e: Exception) {
            Log.w(TAG, "chime: ${e.message}")
            playTone()
            600
        }
    }

    /// Hai tiếng bíp ngắn qua loa (STREAM_MUSIC — to hơn notification trên máy POS).
    private fun playTone() {
        try {
            val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
            tone.startTone(ToneGenerator.TONE_PROP_ACK, 600)
            Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 900)
        } catch (_: Exception) {
        }
    }
}
