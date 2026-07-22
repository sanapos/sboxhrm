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
import io.flutter.plugins.GeneratedPluginRegistrant

class CustomerDisplayActivity : FlutterActivity() {
    override fun getCachedEngineId(): String = ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    companion object {
        const val ENGINE_ID = "sbox_customer_display_engine"
        const val ROUTE = "/customer-display"

        fun ensureEngine(context: Context): FlutterEngine {
            FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
            val engine = FlutterEngine(context.applicationContext)
            try {
                GeneratedPluginRegistrant.registerWith(engine)
            } catch (_: Exception) {
            }
            engine.navigationChannel.setInitialRoute(ROUTE)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            return engine
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
    private var eventSink: EventChannel.EventSink? = null

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun publish(context: Context, json: String) {
        prefs(context).edit().putString(KEY_STATE, json).apply()
        eventSink?.success(json)
    }

    fun read(context: Context): String? = prefs(context).getString(KEY_STATE, null)

    fun listDisplays(context: Context): List<Map<String, Any?>> {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        return dm.displays.map { d ->
            mapOf(
                "id" to d.displayId,
                "name" to (d.name ?: "Display ${d.displayId}"),
                "isPrimary" to (d.displayId == Display.DEFAULT_DISPLAY),
            )
        }
    }

    fun show(activity: FlutterActivity, preferredDisplayId: Int? = null): Boolean {
        val dm = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val secondary = dm.displays.filter { it.displayId != Display.DEFAULT_DISPLAY }
        val target = when {
            preferredDisplayId != null ->
                dm.displays.firstOrNull { it.displayId == preferredDisplayId }
            secondary.isNotEmpty() -> secondary.first()
            else -> null
        }

        if (target != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                CustomerDisplayActivity.ensureEngine(activity)
                val intent = Intent(activity, CustomerDisplayActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
                val opts = ActivityOptions.makeBasic()
                opts.launchDisplayId = target.displayId
                activity.startActivity(intent, opts.toBundle())
                return true
            } catch (_: Exception) {
            }
        }

        if (target != null) {
            try {
                presentation?.dismiss()
                val p = CustomerDisplayPresentation(activity, target)
                p.show()
                presentation = p
                return true
            } catch (_: Exception) {
            }
        }

        return try {
            CustomerDisplayActivity.ensureEngine(activity)
            activity.startActivity(
                Intent(activity, CustomerDisplayActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
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
    }

    fun attachEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }
}
