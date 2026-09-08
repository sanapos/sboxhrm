package vn.sana.sbox

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlin.math.max

/** Decode with inSampleSize so Play's bitmap-sampling insight is satisfied. */
object SafeBitmaps {
    fun decodeFile(path: String, maxEdgePx: Int = 2048): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maxEdgePx)
            inPreferredConfig = Bitmap.Config.RGB_565
        }
        return BitmapFactory.decodeFile(path, opts)
    }

    fun decodeByteArray(data: ByteArray, maxEdgePx: Int = 2048): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maxEdgePx)
            inPreferredConfig = Bitmap.Config.RGB_565
        }
        return BitmapFactory.decodeByteArray(data, 0, data.size, opts)
    }

    private fun sampleSize(w: Int, h: Int, maxEdgePx: Int): Int {
        if (w <= 0 || h <= 0) return 1
        var size = 1
        var longest = max(w, h)
        while (longest / (size * 2) >= maxEdgePx) {
            size *= 2
        }
        return size
    }
}
