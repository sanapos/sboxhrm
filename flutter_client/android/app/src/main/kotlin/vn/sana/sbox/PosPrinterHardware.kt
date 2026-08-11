package vn.sana.sbox

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.usb.UsbManager
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Chẩn đoán + liệt kê Bluetooth đã ghép / USB host (Android 6+).
 * Bổ sung cho print_bluetooth_thermal khi danh sách rỗng hoặc USB không thấy máy.
 */
object PosPrinterHardware {
    const val CHANNEL = "com.sboxhrm/printer_hardware"

    fun handle(activity: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bluetoothDiagnostics" -> result.success(bluetoothDiagnostics(activity))
            "listBondedBluetooth" -> result.success(listBondedBluetooth(activity))
            "requestEnableBluetooth" -> {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                if (adapter == null) {
                    result.success(false)
                    return
                }
                if (adapter.isEnabled) {
                    result.success(true)
                    return
                }
                try {
                    val i = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(i)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("BT_ENABLE", e.message, null)
                }
            }
            "openBluetoothSettings" -> {
                try {
                    val i = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(i)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("BT_SETTINGS", e.message, null)
                }
            }
            "usbDiagnostics" -> result.success(usbDiagnostics(activity))
            else -> result.notImplemented()
        }
    }

    private fun bluetoothDiagnostics(ctx: Context): Map<String, Any?> {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        val bonded = try {
            adapter?.bondedDevices?.size ?: 0
        } catch (_: SecurityException) {
            -1
        }
        return mapOf(
            "hasAdapter" to (adapter != null),
            "enabled" to (adapter?.isEnabled == true),
            "bondedCount" to bonded,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    @Suppress("MissingPermission")
    private fun listBondedBluetooth(ctx: Context): List<Map<String, Any?>> {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        if (!adapter.isEnabled) return emptyList()
        val out = ArrayList<Map<String, Any?>>()
        try {
            val devices: Set<BluetoothDevice> = adapter.bondedDevices ?: emptySet()
            for (d in devices) {
                val name = try {
                    d.name
                } catch (_: SecurityException) {
                    null
                }
                val addr = try {
                    d.address
                } catch (_: SecurityException) {
                    null
                }
                if (addr.isNullOrBlank()) continue
                out.add(
                    mapOf(
                        "name" to (name?.takeIf { it.isNotBlank() } ?: "Bluetooth"),
                        "address" to addr,
                        "bondState" to d.bondState,
                        "type" to d.type,
                    ),
                )
            }
        } catch (e: SecurityException) {
            // Android 12+ thiếu BLUETOOTH_CONNECT
        }
        out.sortBy { (it["name"] as? String)?.lowercase() ?: "" }
        return out
    }

    private fun usbDiagnostics(ctx: Context): Map<String, Any?> {
        val pm = ctx.packageManager
        val hasHost = pm.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
        val usb = ctx.getSystemService(Context.USB_SERVICE) as UsbManager
        val devices = try {
            usb.deviceList?.size ?: 0
        } catch (_: Exception) {
            -1
        }
        return mapOf(
            "hasUsbHostFeature" to hasHost,
            "deviceCount" to devices,
            "sdk" to Build.VERSION.SDK_INT,
            "hint" to when {
                !hasHost -> "Thiet bi khong ho tro USB host (OTG)."
                devices == 0 -> "Khong thay may USB. Cam may in vao cong USB Type-A (khong dung cong sac/ADB). Rut cap PC neu dang cam."
                else -> "Co $devices thiet bi USB."
            },
        )
    }
}
