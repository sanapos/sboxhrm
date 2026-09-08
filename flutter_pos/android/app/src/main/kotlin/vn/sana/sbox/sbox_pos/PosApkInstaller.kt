package vn.sana.sbox.sbox_pos

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Cài APK OTA: PackageInstaller (A6/V2s) + FileProvider fallback.
object PosApkInstaller {
    const val CHANNEL = "com.sboxhrm/apk_install"
    const val ACTION = "vn.sana.sbox.sbox_pos.INSTALL_RESULT"

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "install" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.success("Thiếu đường dẫn APK")
                    return
                }
                val file = File(path)
                if (!file.exists() || file.length() < 100_000L) {
                    result.success("File APK không hợp lệ")
                    return
                }
                try {
                    if (Build.VERSION.SDK_INT >= 26 &&
                        !context.packageManager.canRequestPackageInstalls()
                    ) {
                        val settings = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        settings.data = Uri.parse("package:${context.packageName}")
                        settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(settings)
                        result.success(
                            "Hãy bật «Cho phép từ nguồn này» cho SBOX POS rồi bấm Tải & cài đặt lại.",
                        )
                        return
                    }
                    installSession(context, file)
                    result.success(null)
                } catch (e: Exception) {
                    try {
                        openViewer(context, file)
                        result.success(null)
                    } catch (e2: Exception) {
                        result.success("Không mở được trình cài: ${e.message}")
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun installSession(context: Context, file: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        if (Build.VERSION.SDK_INT >= 21) {
            params.setAppPackageName("sbox.sana.vn.pos.flutter")
        }
        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        try {
            file.inputStream().use { input ->
                session.openWrite("base.apk", 0, file.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val intent = Intent(ACTION).setPackage(context.packageName)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= 31) {
                flags = flags or PendingIntent.FLAG_MUTABLE
            }
            val pi = PendingIntent.getBroadcast(context, sessionId, intent, flags)
            session.commit(pi.intentSender)
        } catch (e: Exception) {
            session.abandon()
            throw e
        } finally {
            session.close()
        }
    }

    private fun openViewer(context: Context, file: File) {
        val intent = Intent(Intent.ACTION_VIEW)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.addCategory(Intent.CATEGORY_DEFAULT)
        if (Build.VERSION.SDK_INT >= 24) {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.ota.fileprovider",
                file,
            )
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.setDataAndType(uri, "application/vnd.android.package-archive")
        } else {
            @Suppress("DEPRECATION")
            intent.setDataAndType(
                Uri.fromFile(file),
                "application/vnd.android.package-archive",
            )
        }
        context.startActivity(intent)
    }
}

class PosApkInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        if (status != PackageInstaller.STATUS_PENDING_USER_ACTION) return
        val confirm = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
        } ?: return
        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(confirm)
    }
}
