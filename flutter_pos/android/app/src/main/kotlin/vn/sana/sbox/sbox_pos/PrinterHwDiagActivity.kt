package vn.sana.sbox.sbox_pos

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import android.widget.Toast

/**
 * Chẩn đoán USB/BT qua adb:
 * adb shell am start -n sbox.sana.vn/vn.sana.sbox.PrinterHwDiagActivity
 * adb logcat -s SBOX_PrinterHwDiag
 */
class PrinterHwDiagActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val hasHost = packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
            val usb = UsbEscPosPrinter.listDevices(this)
            Log.i(TAG, "USB host=$hasHost count=${usb.size}")
            for (d in usb) {
                Log.i(TAG, "USB_DEV ${d["displayName"]} name=${d["deviceName"]} perm=${d["hasPermission"]}")
            }

            val adapter = BluetoothAdapter.getDefaultAdapter()
            val bonded = try {
                adapter?.bondedDevices?.map { d ->
                    val n = try { d.name } catch (_: SecurityException) { "?" }
                    val a = try { d.address } catch (_: SecurityException) { "?" }
                    "$n|$a"
                } ?: emptyList()
            } catch (e: SecurityException) {
                listOf("SecurityException:${e.message}")
            }
            Log.i(
                TAG,
                "BT enabled=${adapter?.isEnabled} bonded=${bonded.size} list=$bonded",
            )

            val msg = "USB=${usb.size} host=$hasHost BT=${if (adapter?.isEnabled == true) "on" else "off"} bonded=${bonded.size}"
            Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Log.e(TAG, "diag failed", e)
            Toast.makeText(this, "Diag error: ${e.message}", Toast.LENGTH_LONG).show()
        }
        finish()
    }

    companion object {
        private const val TAG = "SBOX_PrinterHwDiag"
    }
}
