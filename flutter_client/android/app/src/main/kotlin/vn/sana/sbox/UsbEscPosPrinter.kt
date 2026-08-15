package vn.sana.sbox

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * USB ESC/POS: liá»‡t kÃª cá»•ng, xin quyá»n, ghi bulk OUT.
 * Má»—i mÃ¡y (vid:pid:serial) má»Ÿ/Ä‘Ã³ng riÃªng â€” khÃ´ng dÃ¹ng 1 káº¿t ná»‘i global Ä‘á»ƒ trÃ¡nh Ä‘Ã¡ nhau.
 */
object UsbEscPosPrinter {
    const val CHANNEL = "com.sboxhrm/usb_printer"
    const val EVENTS = "com.sboxhrm/usb_printer_events"
    private const val ACTION_USB_PERMISSION = "com.sboxhrm.USB_PERMISSION"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val writeLocks = HashMap<String, Any>()
    private var eventSink: EventChannel.EventSink? = null
    private var attachDetachReceiver: BroadcastReceiver? = null

    fun attachEventSink(ctx: Context, sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink == null) {
            unregisterAttachDetach(ctx)
            return
        }
        registerAttachDetach(ctx)
    }

    private fun registerAttachDetach(ctx: Context) {
        if (attachDetachReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action ?: return
                val device = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE) as? UsbDevice
                } ?: return
                val kind = when (action) {
                    UsbManager.ACTION_USB_DEVICE_ATTACHED -> "attached"
                    UsbManager.ACTION_USB_DEVICE_DETACHED -> "detached"
                    else -> return
                }
                val serial = try {
                    if (Build.VERSION.SDK_INT >= 21) device.serialNumber else null
                } catch (_: Exception) {
                    null
                }
                val payload = mapOf(
                    "action" to kind,
                    "deviceName" to device.deviceName,
                    "vendorId" to device.vendorId,
                    "productId" to device.productId,
                    "stableId" to "${device.vendorId}:${device.productId}:${serial ?: ""}",
                )
                mainHandler.post { eventSink?.success(payload) }
            }
        }
        attachDetachReceiver = receiver
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.applicationContext.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            ctx.applicationContext.registerReceiver(receiver, filter)
        }
    }

    private fun unregisterAttachDetach(ctx: Context) {
        val receiver = attachDetachReceiver ?: return
        try {
            ctx.applicationContext.unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
        attachDetachReceiver = null
    }

    fun handle(activity: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listDevices" -> {
                try {
                    result.success(listDevices(activity))
                } catch (e: Exception) {
                    result.error("USB_LIST", e.message, null)
                }
            }
            "hasPermission" -> {
                val device = findDevice(activity, call) ?: run {
                    result.success(false)
                    return
                }
                val usb = usbManager(activity)
                result.success(usb.hasPermission(device))
            }
            "requestPermission" -> {
                val device = findDevice(activity, call)
                if (device == null) {
                    result.error("USB_NOT_FOUND", "KhÃ´ng tÃ¬m tháº¥y thiáº¿t bá»‹ USB", null)
                    return
                }
                requestPermission(activity, device) { granted ->
                    result.success(granted)
                }
            }
            "writeBytes" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null || bytes.isEmpty()) {
                    result.error("USB_ARGS", "bytes rá»—ng", null)
                    return
                }
                Thread {
                    try {
                        val ok = writeBytes(activity, call, bytes)
                        mainHandler.post { result.success(ok) }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("USB_WRITE", e.message ?: "write failed", null)
                        }
                    }
                }.start()
            }
            "probeDevice" -> {
                Thread {
                    try {
                        val ok = probeDevice(activity, call)
                        mainHandler.post { result.success(ok) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(false) }
                    }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    private fun usbManager(ctx: Context): UsbManager =
        ctx.getSystemService(Context.USB_SERVICE) as UsbManager

    private fun deviceKey(d: UsbDevice): String {
        val serial = try {
            if (Build.VERSION.SDK_INT >= 21) d.serialNumber ?: "" else ""
        } catch (_: SecurityException) {
            ""
        }
        return "${d.vendorId}:${d.productId}:$serial"
    }

    private fun lockFor(key: String): Any = synchronized(writeLocks) {
        writeLocks.getOrPut(key) { Any() }
    }

    fun listDevices(ctx: Context): List<Map<String, Any?>> {
        val usb = usbManager(ctx)
        val out = ArrayList<Map<String, Any?>>()
        for (device in usb.deviceList.values) {
            val serial = try {
                if (usb.hasPermission(device) && Build.VERSION.SDK_INT >= 21) {
                    device.serialNumber
                } else null
            } catch (_: Exception) {
                null
            }
            val product = try {
                if (Build.VERSION.SDK_INT >= 21) device.productName else null
            } catch (_: Exception) {
                null
            }
            val manufacturer = try {
                if (Build.VERSION.SDK_INT >= 21) device.manufacturerName else null
            } catch (_: Exception) {
                null
            }
            out.add(
                mapOf(
                    "deviceName" to device.deviceName,
                    "vendorId" to device.vendorId,
                    "productId" to device.productId,
                    "deviceId" to device.deviceId,
                    "serialNumber" to serial,
                    "productName" to product,
                    "manufacturerName" to manufacturer,
                    "deviceClass" to device.deviceClass,
                    "hasPermission" to usb.hasPermission(device),
                    "stableId" to "${device.vendorId}:${device.productId}:${serial ?: ""}",
                    "displayName" to buildDisplayName(device, manufacturer, product, serial),
                ),
            )
        }
        out.sortBy { (it["displayName"] as? String)?.lowercase() ?: "" }
        return out
    }

    private fun buildDisplayName(
        device: UsbDevice,
        manufacturer: String?,
        product: String?,
        serial: String?,
    ): String {
        val label = listOfNotNull(
            manufacturer?.takeIf { it.isNotBlank() },
            product?.takeIf { it.isNotBlank() },
        ).joinToString(" ")
        val base = if (label.isNotBlank()) label else "USB ${device.deviceName}"
        val ids = "VID=${device.vendorId.toString(16).uppercase()} PID=${device.productId.toString(16).uppercase()}"
        val sn = serial?.takeIf { it.isNotBlank() }?.let { " Â· SN $it" } ?: ""
        return "$base ($ids$sn)"
    }

    private fun findDevice(ctx: Context, call: MethodCall): UsbDevice? {
        val usb = usbManager(ctx)
        val devices = usb.deviceList.values.toList()
        val deviceName = call.argument<String>("deviceName")?.trim()
        val vendorId = call.argument<Number>("vendorId")?.toInt()
        val productId = call.argument<Number>("productId")?.toInt()
        val serial = call.argument<String>("serialNumber")?.trim()
        val stableId = call.argument<String>("stableId")?.trim()

        // 1) deviceName = Ä‘á»‹nh danh cá»•ng duy nháº¥t khi nhiá»u mÃ¡y USB cÃ¹ng model.
        if (!deviceName.isNullOrEmpty()) {
            devices.firstOrNull { it.deviceName == deviceName }?.let { return it }
        }

        fun readSerial(d: UsbDevice): String {
            return try {
                if (usb.hasPermission(d) && Build.VERSION.SDK_INT >= 21) {
                    d.serialNumber ?: ""
                } else ""
            } catch (_: Exception) {
                ""
            }
        }

        // 2) stableId chá»‰ dÃ¹ng khi cÃ³ serial â€” khÃ´ng gÃ¡n mÃ¡y cÃ²n láº¡i cÃ¹ng VID/PID.
        if (!stableId.isNullOrEmpty()) {
            val parts = stableId.split(":")
            if (parts.size >= 2) {
                val vid = parts[0].toIntOrNull()
                val pid = parts[1].toIntOrNull()
                val sn = parts.drop(2).joinToString(":")
                if (vid != null && pid != null && sn.isNotEmpty()) {
                    val bySn = devices.filter {
                        it.vendorId == vid && it.productId == pid && readSerial(it) == sn
                    }
                    return bySn.singleOrNull()
                }
            }
        }

        // 3) vendorId+productId chá»‰ khi cÃ³ serial.
        if (vendorId != null && productId != null && !serial.isNullOrEmpty()) {
            return devices.singleOrNull {
                it.vendorId == vendorId &&
                    it.productId == productId &&
                    readSerial(it) == serial
            }
        }
        return null
    }

    private fun requestPermission(
        ctx: Context,
        device: UsbDevice,
        onResult: (Boolean) -> Unit,
    ) {
        val usb = usbManager(ctx)
        if (usb.hasPermission(device)) {
            onResult(true)
            return
        }
        val flags = if (Build.VERSION.SDK_INT >= 31) {
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getBroadcast(
            ctx,
            device.deviceId,
            Intent(ACTION_USB_PERMISSION),
            flags,
        )
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != ACTION_USB_PERMISSION) return
                try {
                    ctx.unregisterReceiver(this)
                } catch (_: Exception) {
                }
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                onResult(granted)
            }
        }
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            ctx.registerReceiver(receiver, filter)
        }
        usb.requestPermission(device, pi)
    }

    private fun writeBytes(ctx: Context, call: MethodCall, bytes: ByteArray): Boolean {
        val device = findDevice(ctx, call) ?: return false
        val usb = usbManager(ctx)
        if (!usb.hasPermission(device)) {
            // KhÃ´ng block UI thread â€” caller nÃªn requestPermission trÆ°á»›c.
            var granted = false
            val latch = java.util.concurrent.CountDownLatch(1)
            mainHandler.post {
                requestPermission(ctx, device) {
                    granted = it
                    latch.countDown()
                }
            }
            latch.await(20, java.util.concurrent.TimeUnit.SECONDS)
            if (!granted) return false
        }

        val key = deviceKey(device)
        synchronized(lockFor(key)) {
            val connection = usb.openDevice(device) ?: return false
            try {
                val ifaceOut = findBulkOut(device) ?: return false
                val (intf, endpoint) = ifaceOut
                if (!connection.claimInterface(intf, true)) return false
                try {
                    return writeInChunks(connection, endpoint, bytes)
                } finally {
                    try {
                        connection.releaseInterface(intf)
                    } catch (_: Exception) {
                    }
                }
            } finally {
                try {
                    connection.close()
                } catch (_: Exception) {
                }
            }
        }
    }

    /**
     * Online = Ä‘Ãºng thiáº¿t bá»‹ cÃ²n trong bus + open/claim Ä‘Æ°á»£c.
     * KhÃ´ng ghi DLE/ESC (trÃ¡nh nhiá»…u khi nhiá»u mÃ¡y USB; nhiá»u mÃ¡y táº¯t nguá»“n váº«n nháº­n lá»‡nh).
     */
    private fun probeDevice(ctx: Context, call: MethodCall): Boolean {
        val device = findDevice(ctx, call) ?: return false
        val usb = usbManager(ctx)
        if (!usb.hasPermission(device)) return false
        val key = deviceKey(device)
        synchronized(lockFor(key)) {
            val connection = usb.openDevice(device) ?: return false
            try {
                val ifaceOut = findBulkOut(device) ?: return false
                val (intf, _) = ifaceOut
                if (!connection.claimInterface(intf, true)) return false
                try {
                    return true
                } finally {
                    try {
                        connection.releaseInterface(intf)
                    } catch (_: Exception) {
                    }
                }
            } finally {
                try {
                    connection.close()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun findBulkOut(device: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        // Æ¯u tiÃªn interface printer (class 7), rá»“i bulk OUT báº¥t ká»³.
        val printerIfaces = ArrayList<UsbInterface>()
        val otherIfaces = ArrayList<UsbInterface>()
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == UsbConstants.USB_CLASS_PRINTER) {
                printerIfaces.add(intf)
            } else {
                otherIfaces.add(intf)
            }
        }
        for (intf in printerIfaces + otherIfaces) {
            for (e in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    ep.direction == UsbConstants.USB_DIR_OUT
                ) {
                    return intf to ep
                }
            }
        }
        return null
    }

    private fun writeInChunks(
        connection: UsbDeviceConnection,
        endpoint: UsbEndpoint,
        bytes: ByteArray,
    ): Boolean {
        val chunk = 16384.coerceAtMost(endpoint.maxPacketSize.coerceAtLeast(64) * 64)
        var offset = 0
        while (offset < bytes.size) {
            val end = (offset + chunk).coerceAtMost(bytes.size)
            val n = connection.bulkTransfer(endpoint, bytes, offset, end - offset, 15_000)
            if (n < 0) return false
            offset += n
            if (n == 0) return false
        }
        return true
    }
}
