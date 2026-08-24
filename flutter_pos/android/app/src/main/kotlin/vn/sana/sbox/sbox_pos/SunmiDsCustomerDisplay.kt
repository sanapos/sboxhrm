package vn.sana.sbox.sbox_pos

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import sunmi.ds.DSKernel
import sunmi.ds.callback.IConnectionCallback
import sunmi.ds.callback.IReceiveCallback
import sunmi.ds.callback.ISendCallback
import sunmi.ds.data.DSData
import sunmi.ds.data.DSData.DataType
import sunmi.ds.data.DSFile
import sunmi.ds.data.DSFiles
import sunmi.ds.data.DataPacket
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.text.NumberFormat
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * T1 7" theo docs.sunmi.com (built-in vice screen app):
 * - Chao: TEXT
 * - Bill: ảnh 1024×600 + SHOW_IMG_WELCOME (+ VietQR nhỏ khi CK)
 */
object SunmiDsCustomerDisplay {
    private const val TAG = "SunmiDsCustomerDisplay"
    private const val W = 1024
    private const val H = 600
    @Volatile
    private var kernel: DSKernel? = null

    @Volatile
    private var appContext: Context? = null

    private val connected = AtomicBoolean(false)
    private val money = NumberFormat.getInstance(Locale("vi", "VN"))
    private val mainHandler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val gen = AtomicInteger(0)

    @Volatile
    private var pendingJson: String? = null

    @Volatile
    private var lastJson: String? = null

    /** Bỏ qua publish trùng (updatedAtMs đổi liên tục từ Dart). */
    @Volatile
    private var lastContentKey: String? = null


    private data class BillLine(
        val name: String,
        val qty: Double,
        val unitPrice: Double,
        val lineTotal: Double,
        val note: String,
    )

    private val connCb = object : IConnectionCallback {
        override fun onDisConnect() {
            connected.set(false)
            Log.w(TAG, "DSKernel disconnected")
        }

        override fun onConnected(state: IConnectionCallback.ConnState?) {
            Log.i(TAG, "DSKernel connected: $state")
            when (state) {
                IConnectionCallback.ConnState.AIDL_CONN,
                IConnectionCallback.ConnState.VICE_SERVICE_CONN,
                IConnectionCallback.ConnState.VICE_APP_CONN -> {
                    connected.set(true)
                    mainHandler.post { flushPendingOrLast() }
                }
                else -> {}
            }
        }
    }

    private val receiveCb = object : IReceiveCallback {
        override fun onReceiveData(data: DSData?) {}
        override fun onReceiveFile(file: DSFile?) {}
        override fun onReceiveFiles(files: DSFiles?) {}
        override fun onReceiveCMD(cmd: DSData?) {}
    }

    private val sendCb = object : ISendCallback {
        override fun onSendSuccess(taskId: Long) {
            Log.i(TAG, "send ok taskId=$taskId")
        }

        override fun onSendFail(errorId: Int, errorInfo: String?) {
            Log.e(TAG, "send fail id=$errorId info=$errorInfo")
        }

        override fun onSendProcess(totle: Long, sended: Long) {}
    }

    fun isLikelyAvailable(context: Context): Boolean {
        if (Build.MANUFACTURER.equals("SUNMI", ignoreCase = true)) return true
        return try {
            val sub = Settings.Global.getString(context.contentResolver, "sunmi_sub_model")
            !sub.isNullOrBlank()
        } catch (_: Exception) {
            false
        }
    }

    @Synchronized
    fun ensureInit(context: Context) {
        appContext = context.applicationContext
        if (kernel != null) return
        try {
            val k = DSKernel.newInstance()
            k.init(context.applicationContext, connCb)
            k.addReceiveCallback(receiveCb)
            kernel = k
            Log.i(TAG, "DSKernel init")
        } catch (e: Exception) {
            Log.e(TAG, "DSKernel init failed", e)
            kernel = null
        }
    }

    private fun flushPendingOrLast() {
        val pending = pendingJson
        if (pending != null) {
            pendingJson = null
            showFromJson(pending, force = true)
            return
        }
        val last = lastJson
        if (!last.isNullOrBlank()) {
            showFromJson(last, force = true)
            return
        }
        showIdleWelcome("SBOX POS")
    }

    fun showFromJson(raw: String?, force: Boolean = false) {
        if (!raw.isNullOrBlank()) lastJson = raw
        if (kernel == null) {
            pendingJson = raw
            return
        }
        if (!force && !connected.get()) {
            pendingJson = raw
            return
        }
        if (raw.isNullOrBlank()) {
            lastContentKey = null
            showIdleWelcome("SBOX POS")
            return
        }
        try {
            val j = JSONObject(raw)
            val key = contentKey(j)
            if (!force && key == lastContentKey) {
                Log.i(TAG, "skip duplicate content")
                return
            }
            lastContentKey = key

            val mode = j.optString("mode", "idle").trim().lowercase(Locale.US)
            val store = j.optString("storeName", "").ifBlank { "SBOX POS" }
            val table = j.optString("tableLabel", "").trim()
            val total = j.optDouble("total", 0.0)
            val discount = j.optDouble("discount", 0.0)
            val subtotal = j.optDouble("subtotal", 0.0)
            val lines = j.optJSONArray("lines") ?: JSONArray()
            val paymentQrUrl = j.optString("paymentQrUrl", "").trim()
            val isActive = mode == "active"
            val hasLines = lines.length() > 0

            if (!isActive || (!hasLines && table.isEmpty())) {
                showIdleWithPromos(j, store)
                return
            }

            val title = if (table.isNotEmpty()) table else "Đơn hàng"
            val billLines = mutableListOf<BillLine>()
            val max = minOf(lines.length(), 8)
            for (i in 0 until max) {
                val line = lines.optJSONObject(i) ?: continue
                billLines.add(
                    BillLine(
                        name = line.optString("name", "").trim().ifBlank { "Món" },
                        qty = line.optDouble("qty", 0.0),
                        unitPrice = line.optDouble("unitPrice", 0.0),
                        lineTotal = line.optDouble("lineTotal", 0.0),
                        note = line.optString("note", "").trim(),
                    ),
                )
            }
            val moreCount = (lines.length() - max).coerceAtLeast(0)
            Log.i(TAG, "bill image table=$table lines=${lines.length()} qr=${paymentQrUrl.isNotEmpty()}")
            renderAndSendBill(
                title = title,
                store = store,
                lines = billLines,
                moreCount = moreCount,
                subtotal = subtotal,
                discount = discount,
                total = total,
                paymentQrUrl = paymentQrUrl.ifBlank { null },
            )
        } catch (e: Exception) {
            Log.e(TAG, "showFromJson", e)
            lastContentKey = null
            showIdleWelcome("SBOX POS")
        }
    }

    private fun contentKey(j: JSONObject): String {
        val sb = StringBuilder()
        sb.append(j.optString("mode")).append('|')
        sb.append(j.optString("tableLabel")).append('|')
        sb.append(j.optDouble("total")).append('|')
        sb.append(j.optDouble("discount")).append('|')
        sb.append(j.optString("paymentQrUrl")).append('|')
        sb.append(j.optString("storeName")).append('|')
        val lines = j.optJSONArray("lines")
        if (lines != null) {
            for (i in 0 until lines.length()) {
                val line = lines.optJSONObject(i) ?: continue
                sb.append(line.optString("name")).append(':')
                    .append(line.optDouble("qty")).append(':')
                    .append(line.optDouble("lineTotal")).append(':')
                    .append(line.optString("note")).append(';')
            }
        }
        val promos = j.optJSONArray("promoItems")
        if (promos != null) {
            for (i in 0 until minOf(promos.length(), 12)) {
                sb.append(promos.optJSONObject(i)?.optString("imageUrl") ?: "").append(',')
            }
        }
        return sb.toString()
    }

    fun showText(title: String, content: String) {
        lastContentKey = null
        gen.incrementAndGet()
        showTextTemplate(title, content)
    }

    private fun showIdleWelcome(store: String) {
        gen.incrementAndGet()
        showTextTemplate(store.take(40), "Xin chào quý khách")
    }

    /** Idle: ưu tiên ảnh promo (SHOW_IMG_WELCOME), không có thì TEXT. */
    private fun showIdleWithPromos(j: JSONObject, store: String) {
        val ctx = appContext ?: run {
            showIdleWelcome(store)
            return
        }
        if (kernel == null) {
            showIdleWelcome(store)
            return
        }
        var imageUrl: String? = null
        val promos = j.optJSONArray("promoItems")
        if (promos != null) {
            for (i in 0 until promos.length()) {
                val u = promos.optJSONObject(i)?.optString("imageUrl")?.trim()
                if (!u.isNullOrBlank()) {
                    imageUrl = u
                    break
                }
            }
        }
        if (imageUrl.isNullOrBlank()) {
            showIdleWelcome(store)
            return
        }
        val token = gen.incrementAndGet()
        io.execute {
            if (token != gen.get()) return@execute
            try {
                val bmp = downloadBitmap(imageUrl) ?: run {
                    Log.w(TAG, "idle promo download fail url=$imageUrl")
                    mainHandler.post { showIdleWelcome(store) }
                    return@execute
                }
                val file = resolveWelcomeFile(ctx, token)
                FileOutputStream(file).use { out ->
                    bmp.compress(Bitmap.CompressFormat.JPEG, 88, out)
                }
                bmp.recycle()
                try {
                    file.setReadable(true, false)
                    file.setWritable(true, false)
                } catch (_: Exception) {
                }
                if (!file.exists() || file.length() < 100) {
                    mainHandler.post { showIdleWelcome(store) }
                    return@execute
                }
                Log.i(TAG, "idle welcome image size=${file.length()}")
                sendFullScreenPicture(
                    path = file.absolutePath,
                    token = token,
                    fallbackTitle = store.take(40),
                    fallbackBody = listOf("Xin chào quý khách"),
                    fallbackFooter = null,
                )
            } catch (e: Exception) {
                Log.e(TAG, "showIdleWithPromos", e)
                mainHandler.post { showIdleWelcome(store) }
            }
        }
    }

    /** Docs 2.1 — two lines of text (7"). */
    private fun showTextTemplate(title: String, content: String) {
        val k = kernel ?: return
        try {
            val inner = JSONObject()
                .put("title", title.take(60))
                .put("content", content.take(400))
                .toString()
            val payload = JSONObject()
                .put("dataModel", "TEXT")
                .put("data", inner)
                .toString()
            val pkg = DSKernel.getDSDPackageName() ?: "sunmi.dsd"
            val packet = DataPacket.Builder(DataType.DATA)
                .recPackName(pkg)
                .data(payload)
                .addCallback(sendCb)
                .isReport(true)
                .build()
            k.sendData(packet)
            Log.i(TAG, "TEXT title=${title.take(30)}")
        } catch (e: Exception) {
            Log.e(TAG, "showTextTemplate", e)
        }
    }

    private fun renderAndSendBill(
        title: String,
        store: String,
        lines: List<BillLine>,
        moreCount: Int,
        subtotal: Double,
        discount: Double,
        total: Double,
        paymentQrUrl: String?,
    ) {
        val ctx = appContext ?: return
        if (kernel == null) return
        val token = gen.incrementAndGet()
        io.execute {
            if (token != gen.get()) return@execute
            try {
                var qrBmp: Bitmap? = null
                if (!paymentQrUrl.isNullOrBlank()) {
                    qrBmp = downloadBitmap(paymentQrUrl)
                    Log.i(TAG, "vietqr downloaded=${qrBmp != null}")
                }
                val file = resolveBillFile(ctx, token)
                val bmp = renderBill(
                    title = title,
                    store = store,
                    lines = lines,
                    moreCount = moreCount,
                    subtotal = subtotal,
                    discount = discount,
                    total = total,
                    qrBitmap = qrBmp,
                )
                qrBmp?.recycle()
                FileOutputStream(file).use { out ->
                    bmp.compress(Bitmap.CompressFormat.JPEG, 85, out)
                }
                bmp.recycle()
                try {
                    file.setReadable(true, false)
                    file.setWritable(true, false)
                } catch (_: Exception) {
                }
                val size = file.length()
                Log.i(TAG, "bill file=${file.absolutePath} size=$size")
                if (!file.exists() || size < 100) {
                    val fallback = buildTextFallback(title, lines, total)
                    showTextTemplate(title.take(40), fallback)
                    return@execute
                }
                pruneOldBillFiles(file.parentFile ?: return@execute, keepToken = token)
                if (token != gen.get()) return@execute
                sendFullScreenPicture(
                    file.absolutePath,
                    token,
                    fallbackTitle = title,
                    fallbackBody = lines.map { formatBillTextLine(it) },
                    fallbackFooter = "TỔNG  ${formatMoney(total)}",
                )
            } catch (e: Exception) {
                Log.e(TAG, "renderAndSend", e)
                showTextTemplate(title, "TỔNG  ${formatMoney(total)}")
            }
        }
    }

    private fun downloadBitmap(urlStr: String): Bitmap? {
        return try {
            val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                connectTimeout = 8_000
                readTimeout = 12_000
                instanceFollowRedirects = true
                requestMethod = "GET"
            }
            conn.connect()
            if (conn.responseCode !in 200..299) {
                conn.disconnect()
                return null
            }
            val bytes = conn.inputStream.use { it.readBytes() }
            conn.disconnect()
            if (bytes.size < 200) return null
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (e: Exception) {
            Log.w(TAG, "downloadBitmap: ${e.message}")
            null
        }
    }

    private fun buildTextFallback(title: String, lines: List<BillLine>, total: Double): String {
        return buildString {
            lines.take(4).forEach { append(formatBillTextLine(it)).append('\n') }
            append("TỔNG  ").append(formatMoney(total))
        }.take(400)
    }

    private fun formatBillTextLine(l: BillLine): String =
        "${formatQty(l.qty)}x ${l.name}  ${formatMoney(l.lineTotal)}"

    private fun renderBill(
        title: String,
        store: String,
        lines: List<BillLine>,
        moreCount: Int,
        subtotal: Double,
        discount: Double,
        total: Double,
        qrBitmap: Bitmap?,
    ): Bitmap {
        val bmp = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(Color.parseColor("#0F172A"))
        val pad = 28f
        val hasQr = qrBitmap != null
        val splitX = if (hasQr) 700f else W.toFloat()
        val contentW = splitX - pad * 2
        val colTotal = if (hasQr) 110f else 150f
        val colPrice = if (hasQr) 110f else 150f
        val colQty = if (hasQr) 56f else 72f
        val colName = (contentW - colTotal - colPrice - colQty - 18f).coerceAtLeast(120f)
        val xName = pad
        val xQty = pad + colName + 6f
        val xPrice = xQty + colQty + 6f
        val xTotal = xPrice + colPrice + 6f
        var y = 24f

        val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = if (hasQr) 34f else 40f
            typeface = Typeface.DEFAULT_BOLD
        }
        y += drawTextBlock(c, title, titlePaint, pad, y, contentW) + 4f

        if (store.isNotEmpty() && !store.equals(title, ignoreCase = true)) {
            val storePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#94A3B8")
                textSize = 20f
            }
            y += drawTextBlock(c, store, storePaint, pad, y, contentW) + 6f
        } else {
            y += 6f
        }

        val rule = Paint().apply {
            color = Color.parseColor("#334155")
            strokeWidth = 2f
        }
        c.drawLine(pad, y, splitX - pad, y, rule)
        y += 12f

        val headPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#94A3B8")
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
        }
        drawTextBlock(c, "Sản phẩm", headPaint, xName, y, colName)
        drawRight(c, "SL", headPaint, xQty, y, colQty)
        drawRight(c, "Đ.giá", headPaint, xPrice, y, colPrice)
        drawRight(c, "T.tiền", headPaint, xTotal, y, colTotal)
        y += 26f
        c.drawLine(pad, y, splitX - pad, y, rule)
        y += 10f

        val namePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#F1F5F9")
            textSize = if (hasQr) 22f else 26f
        }
        val numPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#E2E8F0")
            textSize = if (hasQr) 20f else 24f
        }
        val notePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#64748B")
            textSize = 16f
        }

        val footerReserve = if (discount > 0.5) 100f else 72f
        if (lines.isEmpty()) {
            y += drawTextBlock(c, "Đang chọn món…", namePaint, pad, y, contentW)
        } else {
            for (line in lines) {
                if (y > H - footerReserve - 8f) break
                val nameH = layoutHeight(line.name, namePaint, colName.toInt())
                drawTextBlock(c, line.name, namePaint, xName, y, colName)
                drawRight(c, formatQty(line.qty), numPaint, xQty, y, colQty)
                drawRight(c, formatMoney(line.unitPrice), numPaint, xPrice, y, colPrice)
                drawRight(c, formatMoney(line.lineTotal), numPaint, xTotal, y, colTotal)
                y += nameH + 2f
                if (line.note.isNotEmpty()) {
                    val noteH = layoutHeight(line.note, notePaint, colName.toInt())
                    if (y + noteH < H - footerReserve) {
                        y += drawTextBlock(c, line.note, notePaint, xName + 6f, y, colName - 6f) + 4f
                    }
                } else {
                    y += 6f
                }
            }
            if (moreCount > 0 && y < H - footerReserve) {
                val morePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.parseColor("#94A3B8")
                    textSize = 18f
                }
                y += drawTextBlock(c, "+$moreCount món nữa", morePaint, pad, y, contentW)
            }
        }

        val footerPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#38BDF8")
            textSize = if (hasQr) 30f else 36f
            typeface = Typeface.DEFAULT_BOLD
        }
        val subPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#94A3B8")
            textSize = 20f
        }
        var footerBlock = layoutHeight("TỔNG  ${formatMoney(total)}", footerPaint, contentW.toInt())
        if (discount > 0.5) {
            footerBlock += layoutHeight("Giảm  −${formatMoney(discount)}", subPaint, contentW.toInt()) + 6f
        }
        var fy = (H - pad - footerBlock).coerceAtLeast(y + 12f)
        c.drawLine(pad, fy - 10f, splitX - pad, fy - 10f, rule)
        if (discount > 0.5) {
            fy += drawTextBlock(c, "Giảm  −${formatMoney(discount)}", subPaint, pad, fy, contentW) + 4f
        }
        drawTextBlock(c, "TỔNG  ${formatMoney(total)}", footerPaint, pad, fy, contentW)

        if (hasQr && qrBitmap != null) {
            c.drawLine(splitX, pad, splitX, H - pad, rule)
            val qrTitle = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = 20f
                typeface = Typeface.DEFAULT_BOLD
                textAlign = Paint.Align.CENTER
            }
            val qrHint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#94A3B8")
                textSize = 15f
                textAlign = Paint.Align.CENTER
            }
            val cx = (splitX + W) / 2f
            c.drawText("VietQR", cx, 42f, qrTitle)
            c.drawText(formatMoney(total), cx, 68f, qrHint)
            val box = minOf(240f, W - splitX - pad * 2, H - 130f)
            val left = splitX + (W - splitX - box) / 2f
            val top = 88f
            val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
            c.drawRoundRect(
                android.graphics.RectF(left - 6f, top - 6f, left + box + 6f, top + box + 6f),
                8f,
                8f,
                bg,
            )
            c.drawBitmap(
                qrBitmap,
                null,
                android.graphics.RectF(left, top, left + box, top + box),
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG),
            )
            c.drawText("Quét để CK", cx, top + box + 28f, qrHint)
        }
        return bmp
    }

    private fun drawRight(
        c: Canvas,
        text: String,
        paint: TextPaint,
        x: Float,
        y: Float,
        width: Float,
    ) {
        @Suppress("DEPRECATION")
        val layout = StaticLayout(text, paint, width.toInt(), Layout.Alignment.ALIGN_OPPOSITE, 1f, 0f, false)
        c.save()
        c.translate(x, y)
        layout.draw(c)
        c.restore()
    }

    private fun drawTextBlock(
        c: Canvas,
        text: String,
        paint: TextPaint,
        x: Float,
        y: Float,
        width: Float,
    ): Float {
        @Suppress("DEPRECATION")
        val layout = StaticLayout(text, paint, width.toInt(), Layout.Alignment.ALIGN_NORMAL, 1.1f, 0f, false)
        c.save()
        c.translate(x, y)
        layout.draw(c)
        c.restore()
        return layout.height.toFloat()
    }

    private fun layoutHeight(text: String, paint: TextPaint, width: Int): Float {
        @Suppress("DEPRECATION")
        val layout = StaticLayout(text, paint, width.coerceAtLeast(1), Layout.Alignment.ALIGN_NORMAL, 1f, 0f, false)
        return layout.height.toFloat()
    }

    private fun resolveBillFile(ctx: Context, token: Int): File {
        val name = "sbox_cd_bill_$token.jpg"
        return resolveMediaFile(ctx, name)
    }

    private fun resolveWelcomeFile(ctx: Context, token: Int): File {
        val name = "sbox_cd_welcome_$token.jpg"
        return resolveMediaFile(ctx, name)
    }

    private fun resolveMediaFile(ctx: Context, name: String): File {
        @Suppress("DEPRECATION")
        val sd = Environment.getExternalStorageDirectory()
        if (sd != null) {
            val dir = File(sd, "sbox_cd")
            try {
                if (!dir.exists()) dir.mkdirs()
                val f = File(dir, name)
                FileOutputStream(f).use { it.write(byteArrayOf()) }
                f.delete()
                return File(dir, name)
            } catch (e: Exception) {
                Log.w(TAG, "sdcard media dir fail, fallback app files: ${e.message}")
            }
        }
        val alt = ctx.getExternalFilesDir(null) ?: ctx.cacheDir
        if (!alt.exists()) alt.mkdirs()
        return File(alt, name)
    }

    private fun pruneOldBillFiles(dir: File, keepToken: Int) {
        try {
            dir.listFiles { f ->
                f.isFile && f.name.startsWith("sbox_cd_bill_") && f.name.endsWith(".jpg")
            }?.forEach { f ->
                if (!f.name.contains("_${keepToken}.jpg") &&
                    !f.name.contains("_${keepToken - 1}.jpg")
                ) {
                    f.delete()
                }
            }
        } catch (_: Exception) {
        }
    }

    /** Docs 2.3 — single picture: sendFile rồi SHOW_IMG_WELCOME + fileId. */
    private fun sendFullScreenPicture(
        path: String,
        token: Int,
        fallbackTitle: String?,
        fallbackBody: List<String>?,
        fallbackFooter: String?,
    ) {
        val k = kernel ?: return
        if (token != gen.get()) return
        val pkg = DSKernel.getDSDPackageName() ?: "sunmi.dsd"
        try {
            k.sendFile(pkg, path, object : ISendCallback {
                override fun onSendSuccess(fileId: Long) {
                    if (token != gen.get()) return
                    try {
                        val json = JSONObject()
                            .put("dataModel", "SHOW_IMG_WELCOME")
                            .put("data", "default")
                            .toString()
                        k.sendCMD(pkg, json, fileId, sendCb)
                        Log.i(TAG, "SHOW_IMG_WELCOME fileId=$fileId path=$path")
                    } catch (e: Exception) {
                        Log.e(TAG, "sendCMD picture", e)
                    }
                }

                override fun onSendFail(errorId: Int, errorInfo: String?) {
                    Log.e(TAG, "sendFile fail id=$errorId info=$errorInfo — fallback TEXT")
                    if (fallbackTitle != null && fallbackBody != null) {
                        val content = buildString {
                            fallbackBody.take(5).forEach { append(it).append('\n') }
                            if (!fallbackFooter.isNullOrBlank()) append(fallbackFooter)
                        }
                        showTextTemplate(fallbackTitle.take(40), content.take(400))
                    }
                }

                override fun onSendProcess(totle: Long, sended: Long) {}
            })
        } catch (e: Exception) {
            Log.e(TAG, "sendFile", e)
            if (fallbackTitle != null) {
                showTextTemplate(fallbackTitle, fallbackFooter ?: "")
            }
        }
    }

    private fun formatMoney(v: Double): String = "${money.format(v.toLong())}đ"

    private fun formatQty(q: Double): String {
        return if (q == q.toLong().toDouble()) q.toLong().toString() else q.toString()
    }
}
