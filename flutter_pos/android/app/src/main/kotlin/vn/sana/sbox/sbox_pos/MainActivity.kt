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
    private val ACTION_DATA_CODE_RECEIVED = "com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED"
    private val DATA = "data"

    private var scannerEvents: EventChannel.EventSink? = null
    private var scannerReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                    code = intent.getStringExtra("barcode_string")
                        ?: intent.getStringExtra("barcode")
                }
                if (!code.isNullOrBlank()) {
                    runOnUiThread {
                        scannerEvents?.success(code!!.trim())
                    }
                }
            }
        }
        val filter = IntentFilter(ACTION_DATA_CODE_RECEIVED)
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
