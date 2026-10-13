package vn.sana.sbox.sbox_pos

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import java.io.File

/**
 * Bán offline: mã thiết bị (Android ID — giữ qua gỡ / cài lại app), giờ cài app, và bản sao kho đơn offline
 * ra thư mục chung Download/SBOX_POS (không bị xóa khi «Xóa dữ liệu» app; Android ≤ 10 còn giữ cả khi gỡ app).
 */
object OfflineVaultMirror {
    const val CHANNEL = "sbox/offline_vault"
    private const val DIR = "SBOX_POS"

    fun deviceKey(ctx: Context): String? = try {
        Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID)
    } catch (_: Throwable) {
        null
    }

    fun firstInstallTime(ctx: Context): Long? = try {
        @Suppress("DEPRECATION")
        ctx.packageManager.getPackageInfo(ctx.packageName, 0).firstInstallTime
    } catch (_: Throwable) {
        null
    }

    fun write(ctx: Context, name: String, content: String): Boolean = try {
        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = ctx.contentResolver
            val coll = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val rel = Environment.DIRECTORY_DOWNLOADS + "/" + DIR + "/"
            var uri = resolver.query(
                coll, arrayOf(MediaStore.MediaColumns._ID),
                MediaStore.MediaColumns.DISPLAY_NAME + "=? AND " + MediaStore.MediaColumns.RELATIVE_PATH + "=?",
                arrayOf(name, rel), null,
            )?.use { c -> if (c.moveToFirst()) android.content.ContentUris.withAppendedId(coll, c.getLong(0)) else null }
            if (uri == null) {
                val v = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, rel)
                }
                uri = resolver.insert(coll, v)
            }
            if (uri == null) false else {
                resolver.openOutputStream(uri, "wt")?.use { it.write(content.toByteArray(Charsets.UTF_8)) }
                true
            }
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), DIR)
            if (!dir.exists()) dir.mkdirs()
            val tmp = File(dir, "$name.tmp")
            tmp.writeText(content, Charsets.UTF_8)
            tmp.renameTo(File(dir, name))
        }
    } catch (_: Throwable) {
        false
    }

    fun read(ctx: Context, name: String): String? = try {
        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = ctx.contentResolver
            val coll = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val rel = Environment.DIRECTORY_DOWNLOADS + "/" + DIR + "/"
            resolver.query(
                coll, arrayOf(MediaStore.MediaColumns._ID),
                MediaStore.MediaColumns.DISPLAY_NAME + "=? AND " + MediaStore.MediaColumns.RELATIVE_PATH + "=?",
                arrayOf(name, rel), null,
            )?.use { c ->
                if (!c.moveToFirst()) null else {
                    val uri = android.content.ContentUris.withAppendedId(coll, c.getLong(0))
                    resolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
                }
            }
        } else {
            @Suppress("DEPRECATION")
            val f = File(File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), DIR), name)
            if (f.exists()) f.readText(Charsets.UTF_8) else null
        }
    } catch (_: Throwable) {
        null
    }
}
