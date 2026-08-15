package vn.sana.sbox

import android.app.ActivityOptions
import android.app.Presentation
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.lang.ref.WeakReference

class CustomerDisplayActivity : FlutterActivity() {
    override fun getCachedEngineId(): String = ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CustomerDisplayController.registerHost(this)
    }

    override fun onDestroy() {
        CustomerDisplayController.unregisterHost(this)
        super.onDestroy()
    }

    companion object {
        const val ENGINE_ID = "sbox_customer_display_engine"
        const val ROUTE = "/customer-display"
        private const val METHOD = "com.sboxhrm/customer_display"
        private const val EVENTS = "com.sboxhrm/customer_display_events"

        fun ensureEngine(context: Context): FlutterEngine {
            FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
            val engine = FlutterEngine(context.applicationContext)
            try {
                GeneratedPluginRegistrant.registerWith(engine)
            } catch (_: Exception) {
            }
            // Cho phép engine màn phụ đọc/nhận state (cùng channel với MainActivity).
            registerChannels(engine, context.applicationContext)
            engine.navigationChannel.setInitialRoute(ROUTE)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            return engine
        }

        fun registerChannels(engine: FlutterEngine, context: Context) {
            MethodChannel(engine.dartExecutor.binaryMessenger, METHOD)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "listDisplays" ->
                            result.success(CustomerDisplayController.listDisplays(context))
                        "hasSecondaryDisplay" ->
                            result.success(CustomerDisplayController.hasSecondaryDisplay(context))
                        "show" -> result.success(false) // không mở đệ quy từ màn phụ
                        "hide" -> {
                            CustomerDisplayController.hide()
                            result.success(true)
                        }
                        "publish" -> {
                            val json = call.argument<String>("json") ?: ""
                            CustomerDisplayController.publish(context, json)
                            result.success(true)
                        }
                        "read" -> result.success(CustomerDisplayController.read(context))
                        else -> result.notImplemented()
                    }
                }
            EventChannel(engine.dartExecutor.binaryMessenger, EVENTS)
                .setStreamHandler(object : EventChannel.StreamHandler {
                    private var sink: EventChannel.EventSink? = null

                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        sink = events
                        CustomerDisplayController.attachEventSink(events)
                        val current = CustomerDisplayController.read(context)
                        if (!current.isNullOrBlank()) events?.success(current)
                    }

                    override fun onCancel(arguments: Any?) {
                        CustomerDisplayController.detachEventSink(sink)
                        sink = null
                    }
                })
        }
    }
}

class CustomerDisplayPresentation(
    context: Context,
    display: Display,
) : Presentation(context, display) {
    private var flutterView: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val engine = CustomerDisplayActivity.ensureEngine(context)
        val view = FlutterView(context)
        view.attachToFlutterEngine(engine)
        flutterView = view
        setContentView(
            view,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        engine.lifecycleChannel.appIsResumed()
    }

    override fun onStop() {
        flutterView?.detachFromFlutterEngine()
        flutterView = null
        super.onStop()
    }
}

object CustomerDisplayController {
    private const val PREFS = "sbox_customer_display"
    private const val KEY_STATE = "state_json"

    private var presentation: CustomerDisplayPresentation? = null
    private var hostedActivity: WeakReference<CustomerDisplayActivity>? = null
    private val eventSinks = java.util.concurrent.CopyOnWriteArrayList<EventChannel.EventSink>()

    fun registerHost(activity: CustomerDisplayActivity) {
        hostedActivity = WeakReference(activity)
    }

    fun unregisterHost(activity: CustomerDisplayActivity) {
        if (hostedActivity?.get() === activity) hostedActivity = null
    }

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun publish(context: Context, json: String) {
        prefs(context).edit().putString(KEY_STATE, json).apply()
        for (sink in eventSinks) {
            try {
                sink.success(json)
            } catch (_: Exception) {
            }
        }
    }

    fun read(context: Context): String? = prefs(context).getString(KEY_STATE, null)

    fun listDisplays(context: Context): List<Map<String, Any?>> {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        return dm.displays.map { d ->
            mapOf(
                "id" to d.displayId,
                "name" to (d.name ?: "Display ${d.displayId}"),
                "isPrimary" to (d.displayId == Display.DEFAULT_DISPLAY),
                "isSecondary" to isSecondaryDisplay(d),
            )
        }
    }

    /** Màn thật sự phụ (không phải DEFAULT) — máy 1 màn (V2S…) trả rỗng. */
    fun secondaryDisplays(context: Context): List<Display> {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        return dm.displays.filter { isSecondaryDisplay(it) }
    }

    fun hasSecondaryDisplay(context: Context): Boolean =
        secondaryDisplays(context).isNotEmpty()

    private fun isSecondaryDisplay(d: Display): Boolean {
        if (d.displayId == Display.DEFAULT_DISPLAY) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
            if (d.state == Display.STATE_OFF) return false
        }
        val n = (d.name ?: "").lowercase()
        if (n.contains("overlay") || n.contains("virtual") ||
            n.contains("scrcpy") || n.contains("vysor")
        ) {
            return false
        }
        return true
    }

    private fun pickBestSecondary(list: List<Display>): Display {
        return list.firstOrNull { (it.flags and Display.FLAG_PRESENTATION) != 0 }
            ?: list.first()
    }

    fun show(activity: FlutterActivity, preferredDisplayId: Int? = null): Boolean {
        val secondary = secondaryDisplays(activity)
        val target = when {
            preferredDisplayId != null ->
                secondary.firstOrNull { it.displayId == preferredDisplayId }
            secondary.isNotEmpty() -> pickBestSecondary(secondary)
            else -> null
        }

        // Không có màn phụ → KHÔNG mở Activity trên màn chính (tránh V2S bị chiếm UI).
        if (target == null) return false

        hide()

        // Presentation: chỉ vẽ trên màn khách — không tạo tab/task trên màn thu ngân (A7).
        try {
            val p = CustomerDisplayPresentation(activity, target)
            p.show()
            presentation = p
            return true
        } catch (_: Exception) {
        }

        return startActivityOnDisplay(activity, target)
    }

    private fun startActivityOnDisplay(activity: FlutterActivity, target: Display): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            CustomerDisplayActivity.ensureEngine(activity)
            val intent = Intent(activity, CustomerDisplayActivity::class.java)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS,
                )
            val opts = ActivityOptions.makeBasic()
            opts.launchDisplayId = target.displayId
            activity.startActivity(intent, opts.toBundle())
            true
        } catch (_: Exception) {
            false
        }
    }

    fun hide() {
        try {
            presentation?.dismiss()
        } catch (_: Exception) {
        }
        presentation = null
        hostedActivity?.get()?.let { act ->
            try {
                act.finish()
            } catch (_: Exception) {
            }
        }
        hostedActivity = null
    }

    fun attachEventSink(sink: EventChannel.EventSink?) {
        if (sink == null) return
        if (!eventSinks.contains(sink)) eventSinks.add(sink)
    }

    fun detachEventSink(sink: EventChannel.EventSink?) {
        if (sink == null) {
            eventSinks.clear()
            return
        }
        eventSinks.remove(sink)
    }
}
