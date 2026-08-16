package vn.sana.sbox.sbox_pos

import android.app.ActivityOptions
import android.app.Presentation
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Display
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.NumberFormat
import java.util.Locale
import java.util.concurrent.Executors
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
                        "show" -> result.success(false)
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

/** Flutter UI đầy đủ trên màn phụ (nặng — chỉ khi chọn androidFlutter). */
class CustomerDisplayFlutterPresentation(
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

/**
 * T1 nhẹ: chỉ TextView + ImageView (bill + VietQR).
 * Không FlutterEngine thứ 2.
 */
class CustomerDisplayNativePresentation(
    context: Context,
    display: Display,
) : Presentation(context, display) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val money = NumberFormat.getInstance(Locale("vi", "VN"))

    private lateinit var titleView: TextView
    private lateinit var subtitleView: TextView
    private lateinit var linesView: TextView
    private lateinit var totalView: TextView
    private lateinit var hintView: TextView
    private lateinit var qrView: ImageView
    private lateinit var promoView: ImageView

    private var qrLoadToken = 0
    private var promoLoadToken = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = dp(16)
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#0F172A"))
            setPadding(pad, pad, pad, pad)
        }

        titleView = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            typeface = Typeface.DEFAULT_BOLD
            text = "SBOX POS"
        }
        subtitleView = TextView(context).apply {
            setTextColor(Color.parseColor("#94A3B8"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            text = "Xin chào quý khách"
        }
        linesView = TextView(context).apply {
            setTextColor(Color.parseColor("#E2E8F0"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setLineSpacing(0f, 1.25f)
        }
        totalView = TextView(context).apply {
            setTextColor(Color.parseColor("#38BDF8"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.END
            text = "0đ"
        }
        hintView = TextView(context).apply {
            setTextColor(Color.parseColor("#94A3B8"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            text = ""
        }
        qrView = ImageView(context).apply {
            adjustViewBounds = true
            scaleType = ImageView.ScaleType.FIT_CENTER
            visibility = android.view.View.GONE
            setBackgroundColor(Color.WHITE)
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
        promoView = ImageView(context).apply {
            adjustViewBounds = true
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = android.view.View.GONE
        }

        val scroll = ScrollView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
            addView(
                linesView,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
        }

        root.addView(titleView)
        root.addView(subtitleView)
        root.addView(promoView, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(160),
        ).apply { topMargin = dp(10) })
        root.addView(scroll)
        root.addView(totalView, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(8) })
        root.addView(hintView, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(6) })
        root.addView(qrView, LinearLayout.LayoutParams(
            dp(220),
            dp(220),
        ).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            topMargin = dp(8)
        })

        setContentView(root)
        applyJson(CustomerDisplayController.read(context))
    }

    fun applyJson(raw: String?) {
        if (raw.isNullOrBlank()) {
            showIdle(null, null)
            return
        }
        try {
            val j = JSONObject(raw)
            val mode = j.optString("mode", "idle")
            val store = j.optString("storeName", "").ifBlank { "SBOX POS" }
            if (mode != "active") {
                val promo = firstPromoImage(j.optJSONArray("promoItems"))
                showIdle(store, promo)
                return
            }
            val table = j.optString("tableLabel", "")
            val orderNo = j.optString("orderNo", "")
            val total = j.optDouble("total", 0.0)
            val qr = j.optString("paymentQrUrl", "").trim()
            val lines = j.optJSONArray("lines") ?: JSONArray()
            val buf = StringBuilder()
            for (i in 0 until lines.length()) {
                val line = lines.optJSONObject(i) ?: continue
                val name = line.optString("name", "")
                val qty = line.optDouble("qty", 0.0)
                val lineTotal = line.optDouble("lineTotal", 0.0)
                if (name.isBlank()) continue
                buf.append("• ").append(name)
                if (qty > 0) buf.append(" × ").append(fmtQty(qty))
                buf.append("   ").append(money.format(lineTotal)).append("đ\n")
            }
            titleView.text = if (table.isNotBlank()) table else store
            subtitleView.text = buildString {
                if (orderNo.isNotBlank()) append(orderNo)
                if (isNotEmpty() && store.isNotBlank()) append(" · ")
                if (store.isNotBlank()) append(store)
                if (isEmpty()) append("Đơn hàng")
            }
            linesView.text = if (buf.isEmpty()) "Chưa có món" else buf.toString().trim()
            totalView.text = "${money.format(total)}đ"
            promoView.visibility = android.view.View.GONE
            if (qr.isNotEmpty()) {
                hintView.text = "Quét VietQR để thanh toán"
                qrView.visibility = android.view.View.VISIBLE
                loadQr(qr)
            } else {
                hintView.text = ""
                qrView.visibility = android.view.View.GONE
                qrView.setImageDrawable(null)
            }
        } catch (_: Exception) {
            showIdle(null, null)
        }
    }

    private fun showIdle(store: String?, promoUrl: String?) {
        titleView.text = store?.ifBlank { "SBOX POS" } ?: "SBOX POS"
        subtitleView.text = "Xin chào quý khách"
        linesView.text = ""
        totalView.text = ""
        hintView.text = "Chờ phục vụ"
        qrView.visibility = android.view.View.GONE
        qrView.setImageDrawable(null)
        if (!promoUrl.isNullOrBlank()) {
            promoView.visibility = android.view.View.VISIBLE
            loadPromo(promoUrl)
        } else {
            promoView.visibility = android.view.View.GONE
            promoView.setImageDrawable(null)
        }
    }

    private fun firstPromoImage(arr: JSONArray?): String? {
        if (arr == null) return null
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val img = o.optString("imageUrl", "").trim()
            if (img.isNotEmpty()) return img
        }
        return null
    }

    private fun loadQr(url: String) {
        val token = ++qrLoadToken
        io.execute {
            val bmp = downloadBitmap(url, maxSide = 512)
            mainHandler.post {
                if (token != qrLoadToken) return@post
                if (bmp != null) qrView.setImageBitmap(bmp)
            }
        }
    }

    private fun loadPromo(url: String) {
        val token = ++promoLoadToken
        io.execute {
            val bmp = downloadBitmap(url, maxSide = 720)
            mainHandler.post {
                if (token != promoLoadToken) return@post
                if (bmp != null) promoView.setImageBitmap(bmp)
            }
        }
    }

    private fun downloadBitmap(url: String, maxSide: Int): Bitmap? {
        return try {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000
                readTimeout = 10000
                instanceFollowRedirects = true
            }
            conn.inputStream.use { input ->
                val raw = BitmapFactory.decodeStream(input) ?: return null
                val w = raw.width
                val h = raw.height
                val longest = maxOf(w, h)
                if (longest <= maxSide) return raw
                val scale = maxSide.toFloat() / longest
                Bitmap.createScaledBitmap(
                    raw,
                    (w * scale).toInt().coerceAtLeast(1),
                    (h * scale).toInt().coerceAtLeast(1),
                    true,
                )
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun fmtQty(q: Double): String {
        return if (q == q.toLong().toDouble()) q.toLong().toString()
        else String.format(Locale.US, "%.2f", q)
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            v.toFloat(),
            context.resources.displayMetrics,
        ).toInt()

    override fun onStop() {
        super.onStop()
    }
}

object CustomerDisplayController {
    private const val PREFS = "sbox_customer_display"
    private const val KEY_STATE = "state_json"

    private var flutterPresentation: CustomerDisplayFlutterPresentation? = null
    private var nativePresentation: CustomerDisplayNativePresentation? = null
    private var hostedActivity: WeakReference<CustomerDisplayActivity>? = null
    /** true khi đang đẩy bill qua Sunmi DSKernel (T1 7″), không phải Presentation. */
    private var usingDsKernel: Boolean = false
    private var activeMode: String = "t1Native"
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
        try {
            nativePresentation?.applyJson(json)
        } catch (_: Exception) {
        }
        // T1: luon day DSKernel tren may Sunmi (khong phu thuoc activeMode).
        if (SunmiDsCustomerDisplay.isLikelyAvailable(context)) {
            usingDsKernel = true
            try {
                SunmiDsCustomerDisplay.ensureInit(context)
                SunmiDsCustomerDisplay.showFromJson(json)
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

    fun secondaryDisplays(context: Context): List<Display> {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        return dm.displays.filter { isSecondaryDisplay(it) }
    }

    fun hasSecondaryDisplay(context: Context): Boolean =
        secondaryDisplays(context).isNotEmpty() ||
            SunmiDsCustomerDisplay.isLikelyAvailable(context)

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

    fun show(
        activity: FlutterActivity,
        preferredDisplayId: Int? = null,
        mode: String? = null,
    ): Boolean {
        val resolved = (mode ?: "t1Native").trim().lowercase(Locale.US)
        activeMode = when {
            resolved.contains("flutter") || resolved == "android" -> "androidFlutter"
            resolved.contains("window") || resolved == "web" || resolved == "browser" -> "window"
            else -> "t1Native"
        }

        // Window: không mở màn local — chỉ sync qua JSON/API.
        if (activeMode == "window") {
            hidePresentations()
            usingDsKernel = false
            return true
        }

        val secondary = secondaryDisplays(activity)
        val target = when {
            preferredDisplayId != null ->
                secondary.firstOrNull { it.displayId == preferredDisplayId }
            secondary.isNotEmpty() -> pickBestSecondary(secondary)
            else -> null
        }

        hidePresentations()

        // T1: không có DisplayManager secondary → DSKernel / VICE.
        if (target == null) {
            if (activeMode == "t1Native" && SunmiDsCustomerDisplay.isLikelyAvailable(activity)) {
                usingDsKernel = true
                SunmiDsCustomerDisplay.ensureInit(activity)
                SunmiDsCustomerDisplay.showFromJson(read(activity))
                return true
            }
            usingDsKernel = false
            return false
        }

        usingDsKernel = false

        if (activeMode == "androidFlutter") {
            // Presentation trước: không tạo tab/task trên màn thu ngân (A7 C20Lite).
            try {
                val p = CustomerDisplayFlutterPresentation(activity, target)
                p.show()
                flutterPresentation = p
                return true
            } catch (_: Exception) {
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
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
                    return true
                } catch (_: Exception) {
                }
            }
            return false
        }

        // t1Native trên máy có DisplayManager secondary (hiếm trên T1).
        return try {
            val p = CustomerDisplayNativePresentation(activity, target)
            p.show()
            nativePresentation = p
            p.applyJson(read(activity))
            true
        } catch (_: Exception) {
            // Fallback DSKernel nếu Presentation thất bại trên Sunmi.
            if (SunmiDsCustomerDisplay.isLikelyAvailable(activity)) {
                usingDsKernel = true
                SunmiDsCustomerDisplay.ensureInit(activity)
                SunmiDsCustomerDisplay.showFromJson(read(activity))
                true
            } else {
                false
            }
        }
    }

    private fun hidePresentations() {
        try {
            flutterPresentation?.dismiss()
        } catch (_: Exception) {
        }
        flutterPresentation = null
        try {
            nativePresentation?.dismiss()
        } catch (_: Exception) {
        }
        nativePresentation = null
        hostedActivity?.get()?.let { act ->
            try {
                act.finish()
            } catch (_: Exception) {
            }
        }
        hostedActivity = null
    }

    fun hide() {
        hidePresentations()
        if (usingDsKernel) {
            try {
                SunmiDsCustomerDisplay.showText("SBOX POS", "Xin chào quý khách")
            } catch (_: Exception) {
            }
        }
        usingDsKernel = false
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
