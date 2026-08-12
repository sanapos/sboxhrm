package vn.sana.sbox.sbox_pos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CUSTOMER_DISPLAY_CHANNEL = "com.sboxhrm/customer_display"
    private val CUSTOMER_DISPLAY_EVENTS = "com.sboxhrm/customer_display_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // T1 7″ dùng DSKernel (không phải Presentation) — init sớm để HCService sẵn sàng.
        SunmiDsCustomerDisplay.ensureInit(this)

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
    }
}
