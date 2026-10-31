package vn.sana.sbox.sbox_pos

import android.annotation.TargetApi
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import java.io.File
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

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

    private val REL = Environment.DIRECTORY_DOWNLOADS + "/" + DIR + "/"

    // File đã ghi được trong phiên này — ghi đè thẳng, khỏi query MediaStore mỗi phút.
    private val uriCache = ConcurrentHashMap<String, Uri>()

    // Tên insert lỗi trong phiên này — không thử lại mỗi phút (MediaProvider ghi log lỗi mỗi lần).
    private val insertFailed: MutableSet<String> = Collections.synchronizedSet(HashSet())

    /**
     * Bản của chính app: đúng tên, hoặc «tên (n).json» do MediaStore tự đặt khi trùng — mới nhất trước.
     * File của lần cài trước (gỡ / cài lại, «Xóa dữ liệu») bị mồ côi (owner NULL) nên app không thấy;
     * nếu chỉ tìm đúng tên thì mỗi lần ghi lại insert ra một bản «(n)» mới, tới (32) thì
     * MediaStore báo «Failed to build unique file».
     */
    @TargetApi(29)
    private fun ownCopies(ctx: Context, coll: Uri, name: String): List<Uri> {
        val dot = name.lastIndexOf('.')
        val like = if (dot < 0) "$name (%)" else name.substring(0, dot) + " (%)" + name.substring(dot)
        val out = ArrayList<Uri>()
        ctx.contentResolver.query(
            coll, arrayOf(MediaStore.MediaColumns._ID),
            MediaStore.MediaColumns.RELATIVE_PATH + "=? AND " + MediaStore.MediaColumns.OWNER_PACKAGE_NAME + "=? AND (" +
                MediaStore.MediaColumns.DISPLAY_NAME + "=? OR " + MediaStore.MediaColumns.DISPLAY_NAME + " LIKE ?)",
            arrayOf(REL, ctx.packageName, name, like),
            MediaStore.MediaColumns.DATE_MODIFIED + " DESC, " + MediaStore.MediaColumns._ID + " DESC",
        )?.use { c -> while (c.moveToNext()) out.add(ContentUris.withAppendedId(coll, c.getLong(0))) }
        return out
    }

    private fun writeTo(ctx: Context, uri: Uri, content: String): Boolean = try {
        ctx.contentResolver.openOutputStream(uri, "wt")?.use { it.write(content.toByteArray(Charsets.UTF_8)) } != null
    } catch (_: Throwable) {
        false
    }

    fun write(ctx: Context, name: String, content: String): Boolean = try {
        if (Build.VERSION.SDK_INT >= 29) writeQ(ctx, name, content) else {
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

    @TargetApi(29)
    private fun writeQ(ctx: Context, name: String, content: String): Boolean {
        uriCache[name]?.let { if (writeTo(ctx, it, content)) return true else uriCache.remove(name) }
        val resolver = ctx.contentResolver
        val coll = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val own = ownCopies(ctx, coll, name)
        // Dọn các bản «(n)» thừa do bản app cũ sinh ra mỗi phút — giữ bản mới nhất.
        own.drop(1).forEach { try { resolver.delete(it, null, null) } catch (_: Throwable) {} }
        var uri = own.firstOrNull()
        if (uri == null) {
            if (name in insertFailed) return false
            val v = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(MediaStore.MediaColumns.RELATIVE_PATH, REL)
            }
            uri = try { resolver.insert(coll, v) } catch (_: Throwable) { null }
            if (uri == null) {
                insertFailed.add(name)
                return false
            }
        }
        if (!writeTo(ctx, uri, content)) return false
        uriCache[name] = uri
        return true
    }

    fun read(ctx: Context, name: String): String? = try {
        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = ctx.contentResolver
            val coll = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            // Bản của chính app trước; không có thì thử đúng tên (file mồ côi chỉ đọc được khi có quyền bộ nhớ).
            val uri = ownCopies(ctx, coll, name).firstOrNull() ?: resolver.query(
                coll, arrayOf(MediaStore.MediaColumns._ID),
                MediaStore.MediaColumns.DISPLAY_NAME + "=? AND " + MediaStore.MediaColumns.RELATIVE_PATH + "=?",
                arrayOf(name, REL), null,
            )?.use { c -> if (c.moveToFirst()) ContentUris.withAppendedId(coll, c.getLong(0)) else null }
            if (uri == null) null else resolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
        } else {
            @Suppress("DEPRECATION")
            val f = File(File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), DIR), name)
            if (f.exists()) f.readText(Charsets.UTF_8) else null
        }
    } catch (_: Throwable) {
        null
    }
}
