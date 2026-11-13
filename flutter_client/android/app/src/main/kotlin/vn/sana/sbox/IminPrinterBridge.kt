package vn.sana.sbox

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.imin.printer.INeoPrinterCallback
import com.imin.printer.InitPrinterCallback
import com.imin.printer.PrinterHelper
import com.imin.printerlib.Callback
import com.imin.printerlib.IminPrintUtils
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Máy in tích hợp trên máy POS iMin (D1/D4/M2/Swan/Falcon/Swift/Crane…).
 *
 * - SDK 2.0 ([PrinterHelper], dịch vụ `com.imin.printerservice`): Android 12L+ (API ≥ 32).
 * - SDK 1.0 ([IminPrintUtils]): Android ≤ 11 — USB nội bộ, riêng M2-202/203/Pro dùng SPI.
 *   Chọn SDK giống plugin chính hãng imin_printer 0.7.5.
 *
 * SDK chỉ được khởi tạo khi máy đúng là iMin và có lệnh in: SDK 1.0 tạo luồng nền + quét /
 * xin quyền USB ngay lúc khởi tạo, không được chạy trên Sunmi / điện thoại.
 * Mọi lệnh gọi SDK chạy trên một luồng riêng (SDK có thể chặn), trả kết quả về main thread.
 */
object IminPrinterBridge {
    const val CHANNEL = "com.sboxhrm/imin_printer"
    private const val TAG = "IminPrinterBridge"
    private const val SERVICE_PKG = "com.imin.printerservice"

    /// Binder giới hạn ~1MB / giao dịch — ảnh raster hóa đơn dài phải chia nhỏ.
    private const val CHUNK = 16 * 1024

    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "imin-printer") }
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var sdk2Connected = false
    private var sdk2PrinterInit = false
    private var sdk1: IminPrintUtils? = null
    private var sdk1Type: IminPrintUtils.PrintConnectType = IminPrintUtils.PrintConnectType.USB

    fun handle(activity: Context, call: MethodCall, result: MethodChannel.Result) {
        val ctx = activity.applicationContext
        when (call.method) {
            "info" -> result.success(info(ctx))
            "status", "print", "openDrawer", "paperInfo" -> {
                if (!isImin(ctx)) {
                    result.error("NOT_IMIN", "Không phải máy iMin", null)
                    return
                }
                worker.execute {
                    val reply: Any? = try {
                        when (call.method) {
                            "status" -> status(ctx)
                            "print" -> print(
                                ctx,
                                call.argument<ByteArray>("bytes") ?: ByteArray(0),
                                call.argument<Boolean>("openDrawer") == true,
                            )
                            "openDrawer" -> openDrawer(ctx)
                            else -> paperInfo(ctx)
                        }
                    } catch (t: Throwable) {
                        Log.w(TAG, "${call.method} failed", t)
                        main.post { result.error("IMIN", t.message, null) }
                        return@execute
                    }
                    main.post { result.success(reply) }
                }
            }
            else -> result.notImplemented()
        }
    }

    // ---- Nhận biết máy -------------------------------------------------------------------

    private fun prop(key: String): String = try {
        val c = Class.forName("android.os.SystemProperties")
        (c.getMethod("get", String::class.java).invoke(null, key) as? String).orEmpty().trim()
    } catch (_: Throwable) {
        ""
    }

    private fun serviceInstalled(ctx: Context): Boolean = try {
        ctx.packageManager.getPackageInfo(SERVICE_PKG, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    } catch (_: Throwable) {
        false
    }

    fun isImin(ctx: Context): Boolean {
        val bm = "${Build.BRAND} ${Build.MANUFACTURER}".lowercase()
        return bm.contains("imin") ||
            prop("ro.neostra.imin_model").isNotEmpty() ||
            serviceInstalled(ctx)
    }

    private fun useSdk2(): Boolean = Build.VERSION.SDK_INT >= 32

    /// Tên model iMin (vd. "D4-503", "M2-202", "Swan 2"); Build.MODEL đời mới là mã nội bộ (I23M02…).
    private fun model(): String {
        val m = prop("ro.neostra.imin_model")
        if (m.isNotEmpty()) return m
        return Build.MODEL.orEmpty()
    }

    private fun isSpiModel(model: String): Boolean =
        model.contains("M2-202") || model.contains("M2-203") || model.contains("M2-Pro")

    private fun info(ctx: Context): Map<String, Any?> {
        val imin = isImin(ctx)
        val model = model()
        return mapOf(
            "isImin" to imin,
            "sdk" to if (!imin) 0 else if (useSdk2()) 2 else 1,
            "model" to model,
            "buildModel" to Build.MODEL,
            "connectType" to if (!imin) "" else if (useSdk2()) "SERVICE" else if (isSpiModel(model)) "SPI" else "USB",
            "serviceInstalled" to serviceInstalled(ctx),
            "androidSdk" to Build.VERSION.SDK_INT,
        )
    }

    // ---- Khởi tạo SDK (chỉ gọi trên luồng worker) -----------------------------------------

    private fun ensureSdk2(ctx: Context): Boolean {
        if (!sdk2Connected) {
            val latch = CountDownLatch(1)
            val started = PrinterHelper.getInstance().initPrinterService(
                ctx,
                object : InitPrinterCallback {
                    override fun onConnected() {
                        sdk2Connected = true
                        latch.countDown()
                    }

                    override fun onDisconnected() {
                        sdk2Connected = false
                        sdk2PrinterInit = false
                    }
                },
            )
            if (started) latch.await(5, TimeUnit.SECONDS)
            if (!sdk2Connected) {
                Log.w(TAG, "SDK2: không nối được $SERVICE_PKG (started=$started)")
                return false
            }
        }
        if (!sdk2PrinterInit) {
            val latch = CountDownLatch(1)
            PrinterHelper.getInstance().initPrinter(ctx.packageName, callback { latch.countDown() })
            latch.await(3, TimeUnit.SECONDS)
            sdk2PrinterInit = true
        }
        return true
    }

    private fun ensureSdk1(ctx: Context): IminPrintUtils {
        sdk1?.let { return it }
        val type = if (isSpiModel(model())) {
            IminPrintUtils.PrintConnectType.SPI
        } else {
            IminPrintUtils.PrintConnectType.USB
        }
        val u = IminPrintUtils.getInstance(ctx)
        u.initPrinter(type)
        sdk1Type = type
        sdk1 = u
        return u
    }

    private fun callback(done: () -> Unit) = object : INeoPrinterCallback() {
        override fun onRunResult(isSuccess: Boolean) = done()
        override fun onReturnString(result: String?) = done()
        override fun onRaiseException(code: Int, msg: String?) = done()
        override fun onPrintResult(code: Int, msg: String?) = done()
    }

    // ---- Lệnh ---------------------------------------------------------------------------

    /// Mã trạng thái iMin: 0 bình thường, 1 chưa kết nối, 3 mở nắp, 4 dao kẹt, 5 quá nhiệt,
    /// 7 hết giấy, 8 sắp hết giấy, -1/2/6/99 lỗi. -1 cũng dùng khi không đọc được.
    private fun status(ctx: Context): Int {
        if (useSdk2()) {
            if (!ensureSdk2(ctx)) return -1
            return PrinterHelper.getInstance().printerStatus
        }
        val u = ensureSdk1(ctx)
        if (sdk1Type == IminPrintUtils.PrintConnectType.SPI) {
            var code = -1
            val latch = CountDownLatch(1)
            u.getPrinterStatus(sdk1Type, Callback { s ->
                code = s
                latch.countDown()
            })
            latch.await(3, TimeUnit.SECONDS)
            return code
        }
        return u.getPrinterStatus(sdk1Type)
    }

    private fun blocking(code: Int): Boolean =
        code == 1 || code == 3 || code == 4 || code == 5 || code == 7

    private fun print(ctx: Context, bytes: ByteArray, drawer: Boolean): Map<String, Any?> {
        val before = try {
            status(ctx)
        } catch (t: Throwable) {
            Log.w(TAG, "status before print", t)
            -1
        }
        if (blocking(before)) return mapOf("ok" to false, "status" to before)
        if (useSdk2()) {
            if (!ensureSdk2(ctx)) return mapOf("ok" to false, "status" to -1)
            val h = PrinterHelper.getInstance()
            var i = 0
            while (i < bytes.size) {
                val end = minOf(i + CHUNK, bytes.size)
                h.sendRAWData(bytes.copyOfRange(i, end), null)
                i = end
            }
        } else {
            val u = ensureSdk1(ctx)
            u.sendRAWData(bytes)
        }
        if (drawer) openDrawer(ctx)
        val after = try {
            status(ctx)
        } catch (_: Throwable) {
            -1
        }
        return mapOf("ok" to !blocking(after), "status" to after)
    }

    private fun openDrawer(ctx: Context): Boolean {
        if (useSdk2()) {
            if (!ensureSdk2(ctx)) return false
            PrinterHelper.getInstance().openDrawer()
            return true
        }
        return openDrawerGpio()
    }

    /// SDK 1.0 không có API két: ghi GPIO như Utils.opencashBox() của imin_printer (BSD-3).
    private fun openDrawerGpio(): Boolean {
        val model = model()
        val platform = prop("ro.board.platform")
        val path = if (model == "D1" || model == "D1-Pro" || model == "Falcon 1" ||
            model == "I22T01" || model == "TF1-11" || platform.equals("ums512", ignoreCase = true)
        ) {
            "/sys/extcon-usb-gpio/cashbox_en"
        } else {
            "/sys/class/neostra_gpioctl/dev/gpioctl"
        }
        return try {
            val p = Runtime.getRuntime().exec("sh")
            p.outputStream.use { it.write("echo 1 > $path\nexit\n".toByteArray()) }
            p.waitFor(2, TimeUnit.SECONDS)
            true
        } catch (t: Throwable) {
            Log.w(TAG, "open drawer gpio", t)
            false
        }
    }

    /// Khổ giấy máy báo (chỉ SDK 2.0): chỉ số + danh sách loại giấy, Dart tự suy 58/80.
    private fun paperInfo(ctx: Context): Map<String, Any?> {
        if (!useSdk2() || !ensureSdk2(ctx)) return mapOf("type" to -1, "types" to emptyList<String>())
        val h = PrinterHelper.getInstance()
        val types = try {
            h.printerPaperTypeList ?: emptyList()
        } catch (_: Throwable) {
            emptyList<String>()
        }
        return mapOf("type" to h.printerPaperType, "types" to types)
    }
}
