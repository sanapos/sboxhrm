package com.example.zkteco_flutter_client

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.sboxhrm/file_saver"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveFile") {
                    val bytes = call.argument<ByteArray>("bytes")
                    val filename = call.argument<String>("filename")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                    if (bytes == null || filename == null) {
                        result.error("INVALID_ARGS", "bytes and filename required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val savedUri = saveFileToMediaStore(bytes, filename, mimeType)
                        result.success(savedUri)
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun saveFileToMediaStore(bytes: ByteArray, filename: String, mimeType: String): String {
        val isImage = mimeType.startsWith("image/")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ (API 29+): Use MediaStore (scoped storage)
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                if (isImage) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/SBOX HRM")
                } else {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/SBOX HRM")
                }
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val collection = if (isImage) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }

            val uri = contentResolver.insert(collection, contentValues)
                ?: throw Exception("Failed to create MediaStore entry")

            contentResolver.openOutputStream(uri)?.use { os ->
                os.write(bytes)
            } ?: throw Exception("Failed to open output stream")

            contentValues.clear()
            contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, contentValues, null, null)

            return uri.toString()
        } else {
            // Android 9 and below: Write directly to public directory
            val dir = if (isImage) {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            } else {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            }
            val subDir = java.io.File(dir, "SBOX HRM")
            if (!subDir.exists()) subDir.mkdirs()

            val file = java.io.File(subDir, filename)
            file.writeBytes(bytes)
            return file.absolutePath
        }
    }
}
