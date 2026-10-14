package vn.sana.sbox.sbox_pos

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CUSTOMER_DISPLAY_CHANNEL = "com.sboxhrm/customer_display"
    private val CUSTOMER_DISPLAY_EVENTS = "com.sboxhrm/customer_display_events"
    private val SCANNER_CHANNEL = "com.sboxhrm/sunmi_scanner"
    private val SCANNER_CONFIG_CHANNEL = "com.sboxhrm/scanner_config"
    private val DATA = "data"

    /// Broadcast của máy quét / máy kiểm kho cầm tay phổ biến (máy để chế độ «Broadcast / Intent»).
    /// Zebra DataWedge, Honeywell, app đọc RFID…: cài Intent action = vn.sana.sbox.SCAN, extra = data
    /// (hoặc nhập action / extra riêng trong app — [customAction]).
    private val KNOWN_ACTIONS = listOf(
        "com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED", // Sunmi
        "android.intent.ACTION_DECODE_DATA",            // Urovo
        "nlscan.action.SCANNER_RESULT",                 // Newland
        "android.intent.action.SCANRESULT",             // iData
        "com.scanner.broadcast",                        // Chainway
        "com.android.server.scannerservice.broadcast",  // Seuic / Autoid
        "com.android.serial.BARCODEPORT_RECEIVEDDATA_ACTION",
        "vn.sana.sbox.SCAN",                            // chuẩn SBOX cho máy tự cài
    )
    private val KNOWN_EXTRAS = listOf(
        "data", "barcode_string", "SCAN_BARCODE1", "value", "scannerdata",
        "com.symbol.datawedge.data_string", "barcodeData", "barcode", "decode_rslt",
        "EXTRA_BARCODE_DECODING_DATA", "epc", "rfid", "code",
    )
    private var customAction: String? = null
    private var customExtra: String? = null

    private var scannerEvents: EventChannel.EventSink? = null
    private var scannerReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OfflineVaultMirror.CHANNEL)
            .setMethodCallHandler { call, result ->
                val ctx = applicationContext
                when (call.method) {
                    "deviceKey" -> result.success(OfflineVaultMirror.deviceKey(ctx))
                    "firstInstallTime" -> result.success(OfflineVaultMirror.firstInstallTime(ctx))
                    "write" -> {
                        val name = call.argument<String>("name") ?: ""
                        val content = call.argument<String>("content") ?: ""
                        Thread { val ok = OfflineVaultMirror.write(ctx, name, content)
                            runOnUiThread { result.success(ok) } }.start()
                    }
                    "read" -> {
                        val name = call.argument<String>("name") ?: ""
                        Thread { val txt = OfflineVaultMirror.read(ctx, name)
                            runOnUiThread { result.success(txt) } }.start()
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NetworkProbe.CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "info") result.success(NetworkProbe.info(applicationContext))
                else result.notImplemented()
            }

        // T1 7" uses DSKernel (not Presentation) — init early for HCService.
        SunmiDsCustomerDisplay.ensureInit(this)

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCANNER_CONFIG_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setCustom" -> {
                        customAction = call.argument<String>("action")?.trim()?.ifEmpty { null }
                        customExtra = call.argument<String>("extra")?.trim()?.ifEmpty { null }
                        if (scannerReceiver != null) {
                            unregisterScannerReceiver()
                            registerScannerReceiver()
                        }
                        result.success(true)
                    }
                    "knownActions" -> result.success(KNOWN_ACTIONS)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CUSTOMER_DISPLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listDisplays" ->
                        result.success(CustomerDisplayController.listDisplays(this))
                    "hasSecondaryDisplay" ->
                        result.success(CustomerDisplayController.hasSecondaryDisplay(this))
                    "show" -> {
                        val displayId = call.argument<Int>("displayId")
                        val mode = call.argument<String>("mode")
                        result.success(CustomerDisplayController.show(this, displayId, mode))
                    }
                    "hide" -> {
                        CustomerDisplayController.hide()
                        result.success(true)
                    }
                    "setAuth" -> {
                        LeTrust.setAuth(call.argument<String>("token"), call.argument<String>("baseUrl"))
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PosTts.CHANNEL)
            .setMethodCallHandler { call, result ->
                PosTts.handle(this, call, result)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PosApkInstaller.CHANNEL)
            .setMethodCallHandler { call, result ->
                PosApkInstaller.handle(this, call, result)
            }
    }

    /// Lấy chuỗi mã trong intent: extra tự cài → các extra quen thuộc → mảng byte → chuỗi duy nhất.
    private fun extractScanText(intent: Intent): String? {
        val extras = intent.extras ?: return null
        val keys = listOfNotNull(customExtra) + KNOWN_EXTRAS
        for (k in keys) {
            val v = extras.get(k) ?: continue
            when (v) {
                is String -> if (v.isNotBlank()) return v
                is ByteArray -> {
                    val len = extras.getInt("length", v.size).coerceIn(0, v.size)
                    val txt = String(v, 0, len, Charsets.UTF_8)
                    if (txt.isNotBlank()) return txt
                }
                is Array<*> -> {
                    val txt = v.filterIsInstance<String>().joinToString("\n")
                    if (txt.isNotBlank()) return txt
                }
                is ArrayList<*> -> {
                    val txt = v.filterIsInstance<String>().joinToString("\n")
                    if (txt.isNotBlank()) return txt
                }
            }
        }
        val strings = extras.keySet().mapNotNull { extras.get(it) as? String }.filter { it.isNotBlank() }
        return strings.singleOrNull()
    }

    private fun registerScannerReceiver() {
        if (scannerReceiver != null) return
        scannerReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val text = extractScanText(intent) ?: return
                // Đầu đọc RFID có thể gửi cả lô EPC trong một broadcast.
                val codes = text.split('\n', '\r', ',', ';', '\t')
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                if (codes.isEmpty()) return
                runOnUiThread {
                    for (c in codes) scannerEvents?.success(c)
                }
            }
        }
        val filter = IntentFilter()
        for (a in KNOWN_ACTIONS) filter.addAction(a)
        customAction?.let { if (!KNOWN_ACTIONS.contains(it)) filter.addAction(it) }
        if (Build.VERSION.SDK_INT >= 33) {
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
        PosTts.shutdown()
        super.onDestroy()
    }
}
