package vn.sana.sbox

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val FILE_CHANNEL = "com.sboxhrm/file_saver"
    private val SCANNER_CHANNEL = "com.sboxhrm/sunmi_scanner"

    private val ACTION_DATA_CODE_RECEIVED = "com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED"
    private val DATA = "data"

    private var scannerEvents: EventChannel.EventSink? = null
    private var scannerReceiver: BroadcastReceiver? = null

    private val CUSTOMER_DISPLAY_CHANNEL = "com.sboxhrm/customer_display"
    private val CUSTOMER_DISPLAY_EVENTS = "com.sboxhrm/customer_display_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL)
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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCANNER_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    scannerEvents = events
                    registerScannerReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterScannerReceiver()
                    scannerEvents = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CUSTOMER_DISPLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listDisplays" -> result.success(CustomerDisplayController.listDisplays(this))
                    "hasSecondaryDisplay" ->
                        result.success(CustomerDisplayController.hasSecondaryDisplay(this))
                    "show" -> {
                        val displayId = call.argument<Int>("displayId")
                        result.success(CustomerDisplayController.show(this, displayId))
                    }
                    "hide" -> {
                        CustomerDisplayController.hide()
                        result.success(true)
                    }
                    "publish" -> {
                        val json = call.argument<String>("json") ?: ""
                        CustomerDisplayController.publish(this, json)
                        result.success(true)
                    }
                    "read" -> result.success(CustomerDisplayController.read(this))
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CUSTOMER_DISPLAY_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var sink: EventChannel.EventSink? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    CustomerDisplayController.attachEventSink(events)
                    val current = CustomerDisplayController.read(this@MainActivity)
                    if (!current.isNullOrBlank()) events?.success(current)
                }

                override fun onCancel(arguments: Any?) {
                    CustomerDisplayController.detachEventSink(sink)
                    sink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UsbEscPosPrinter.CHANNEL)
            .setMethodCallHandler { call, result ->
                UsbEscPosPrinter.handle(this, call, result)
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, UsbEscPosPrinter.EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    UsbEscPosPrinter.attachEventSink(this@MainActivity, events)
                }

                override fun onCancel(arguments: Any?) {
                    UsbEscPosPrinter.attachEventSink(this@MainActivity, null)
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PosPrinterHardware.CHANNEL)
            .setMethodCallHandler { call, result ->
                PosPrinterHardware.handle(this, call, result)
            }
    }

    private fun registerScannerReceiver() {
        if (scannerReceiver != null) return
        scannerReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val action = intent.action ?: return
                if (action != ACTION_DATA_CODE_RECEIVED) return
                var code = intent.getStringExtra(DATA)
                if (code.isNullOrBlank()) {
                    // Một số firmware dùng key khác
                    code = intent.getStringExtra("barcode_string")
                        ?: intent.getStringExtra("barcode")
                }
                if (!code.isNullOrBlank()) {
                    activity?.runOnUiThread {
                        scannerEvents?.success(code.trim())
                    }
                }
            }
        }
        val filter = IntentFilter(ACTION_DATA_CODE_RECEIVED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(scannerReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(scannerReceiver, filter)
        }
    }

    private fun unregisterScannerReceiver() {
        val receiver = scannerReceiver ?: return
        try {
            unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
        scannerReceiver = null
    }

    override fun onDestroy() {
        unregisterScannerReceiver()
        scannerEvents = null
        super.onDestroy()
    }

    private fun saveFileToMediaStore(bytes: ByteArray, filename: String, mimeType: String): String {
        val isImage = mimeType.startsWith("image/")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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
