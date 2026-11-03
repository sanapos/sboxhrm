package vn.sana.sbox

import android.app.Activity
import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Máy bếp (SBOX KDS): chuông, loa ngoài, giữ màn hình sáng khi đang mở màn bếp.
/// Cùng hành vi kênh `com.sboxhrm/tts` của flutter_pos (PosTts.kt) cho bản Android 6.
object KdsDevice {
    const val CHANNEL = "com.sboxhrm/kds_device"
    private const val TAG = "KdsDevice"

    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        val am = activity.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        when (call.method) {
            "audioState" -> result.success(
                mapOf(
                    "music" to am.getStreamVolume(AudioManager.STREAM_MUSIC),
                    "musicMax" to am.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                )
            )
            // Nâng loa ngoài lên tối thiểu [percent]% (không hạ nếu đang to hơn). Trả mức mới.
            "ensureVolume" -> {
                val pct = (call.argument<Int>("percent") ?: 60).coerceIn(10, 100)
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val want = (max * pct + 99) / 100
                if (am.getStreamVolume(AudioManager.STREAM_MUSIC) < want) {
                    try {
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, want, 0)
                    } catch (e: Exception) {
                        // Chế độ Không làm phiền có thể chặn đổi âm lượng.
                        Log.w(TAG, "setStreamVolume: ${e.message}")
                    }
                }
                result.success(am.getStreamVolume(AudioManager.STREAM_MUSIC))
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
            "keepScreenOn" -> {
                val on = call.argument<Boolean>("on") ?: true
                activity.runOnUiThread {
                    if (on) {
                        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(true)
                }
            }
            else -> result.notImplemented()
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

    private fun playTone() {
        try {
            val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
            tone.startTone(ToneGenerator.TONE_PROP_ACK, 600)
            Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 900)
        } catch (_: Exception) {
        }
    }
}
