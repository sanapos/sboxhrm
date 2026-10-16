package vn.sana.sbox

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.hoho.android.usbserial.driver.UsbSerialDriver
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Cân điện tử qua cáp USB-Serial trên Android (máy POS / máy tính bảng có cổng USB host).
 * Chip cáp hỗ trợ (thư viện usb-serial-for-android): CH340/CH341, PL2303, CP210x, FTDI, CDC-ACM.
 * Dữ liệu cân đẩy về Dart qua EventChannel (ByteArray); lỗi / rút cáp gửi map {"error": "..."}.
 */
object UsbSerialScale {
    const val CHANNEL = "com.sboxhrm/usb_scale"
    const val EVENTS = "com.sboxhrm/usb_scale_data"
    private const val ACTION_PERMISSION = "com.sboxhrm.USB_SCALE_PERMISSION"

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var port: UsbSerialPort? = null
    private var io: SerialInputOutputManager? = null

    fun attachSink(s: EventChannel.EventSink?) {
        sink = s
    }

    private fun usb(ctx: Context) = ctx.getSystemService(Context.USB_SERVICE) as UsbManager

    private fun drivers(ctx: Context): List<UsbSerialDriver> =
        UsbSerialProber.getDefaultProber().findAllDrivers(usb(ctx))

    /** «vid:pid» dạng hex 4 số — khóa chọn cân (cắm lại cổng khác vẫn nhận). */
    private fun key(d: UsbSerialDriver) =
        String.format("%04x:%04x", d.device.vendorId, d.device.productId)

    private fun chipName(d: UsbSerialDriver): String =
        d.javaClass.simpleName.removeSuffix("SerialDriver").ifEmpty { "USB-Serial" }

    fun handle(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listPorts" -> try {
                val u = usb(ctx)
                result.success(drivers(ctx).map {
                    mapOf(
                        "key" to key(it),
                        "name" to "${key(it)} · ${chipName(it)}" +
                            (it.device.productName?.let { n -> " · $n" } ?: ""),
                        "hasPermission" to u.hasPermission(it.device),
                    )
                })
            } catch (e: Exception) {
                result.error("SCALE_LIST", e.message, null)
            }
            "open" -> open(ctx, call, result)
            "write" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val p = port
                if (bytes == null || p == null) {
                    result.success(false)
                    return
                }
                Thread {
                    val ok = try {
                        p.write(bytes, 500); true
                    } catch (_: Exception) {
                        false
                    }
                    main.post { result.success(ok) }
                }.start()
            }
            "close" -> {
                close()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun open(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        close()
        val wanted = (call.argument<String>("key") ?: "").lowercase()
        val all = try {
            drivers(ctx)
        } catch (e: Exception) {
            result.error("SCALE_OPEN", "Máy không hỗ trợ USB host: ${e.message}", null)
            return
        }
        if (all.isEmpty()) {
            result.error("SCALE_OPEN", "Không thấy cáp cân USB — cắm cáp vào cổng USB của máy (cáp OTG nếu là máy tính bảng)", null)
            return
        }
        val driver = all.firstOrNull { key(it) == wanted } ?: if (wanted.isEmpty()) all.first() else null
        if (driver == null) {
            result.error(
                "SCALE_OPEN",
                "Không thấy cân $wanted — đang có: ${all.joinToString { key(it) }}",
                null,
            )
            return
        }
        withPermission(ctx, driver) { granted ->
            if (!granted) {
                result.error("SCALE_PERMISSION", "Chưa cho phép SBOX dùng cáp cân USB — bấm «Cho phép» khi máy hỏi", null)
                return@withPermission
            }
            try {
                val conn = usb(ctx).openDevice(driver.device)
                    ?: throw IllegalStateException("Không mở được cáp cân USB")
                val p = driver.ports.first()
                p.open(conn)
                p.setParameters(
                    call.argument<Int>("baud") ?: 9600,
                    call.argument<Int>("dataBits") ?: 8,
                    if ((call.argument<Int>("stopBits") ?: 1) == 2) UsbSerialPort.STOPBITS_2 else UsbSerialPort.STOPBITS_1,
                    when (call.argument<String>("parity")) {
                        "odd" -> UsbSerialPort.PARITY_ODD
                        "even" -> UsbSerialPort.PARITY_EVEN
                        else -> UsbSerialPort.PARITY_NONE
                    },
                )
                // Nhiều cân lấy tín hiệu bắt tay từ DTR / RTS.
                try {
                    p.dtr = true
                    p.rts = true
                } catch (_: Exception) {
                }
                port = p
                val manager = SerialInputOutputManager(p, object : SerialInputOutputManager.Listener {
                    override fun onNewData(data: ByteArray) {
                        main.post { sink?.success(data) }
                    }

                    override fun onRunError(e: Exception) {
                        main.post { sink?.success(mapOf("error" to "Mất kết nối cân (rút cáp?)")) }
                    }
                })
                io = manager
                manager.start()
                result.success(true)
            } catch (e: Exception) {
                close()
                result.error("SCALE_OPEN", e.message ?: "Không mở được cân", null)
            }
        }
    }

    private fun withPermission(ctx: Context, driver: UsbSerialDriver, onResult: (Boolean) -> Unit) {
        val u = usb(ctx)
        if (u.hasPermission(driver.device)) {
            onResult(true)
            return
        }
        // Android 14+: PendingIntent MUTABLE phải là intent tường minh (có package) — thiếu là lỗi ngay.
        val intent = Intent(ACTION_PERMISSION).setPackage(ctx.packageName)
        val flags = if (Build.VERSION.SDK_INT >= 31) {
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getBroadcast(ctx, driver.device.deviceId, intent, flags)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, i: Intent?) {
                if (i?.action != ACTION_PERMISSION) return
                try {
                    ctx.unregisterReceiver(this)
                } catch (_: Exception) {
                }
                onResult(i.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
            }
        }
        val filter = IntentFilter(ACTION_PERMISSION)
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            ctx.registerReceiver(receiver, filter)
        }
        u.requestPermission(driver.device, pi)
    }

    fun close() {
        try {
            io?.stop()
        } catch (_: Exception) {
        }
        io = null
        try {
            port?.close()
        } catch (_: Exception) {
        }
        port = null
    }
}
