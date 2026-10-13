package vn.sana.sbox.sbox_pos

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager

/** Mạng hiện tại cho báo cáo «Mạng cửa hàng»: loại kết nối, sóng Wi‑Fi (dBm), tốc độ liên kết. */
object NetworkProbe {
    const val CHANNEL = "sbox/network_probe"

    fun info(ctx: Context): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        try {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.activeNetwork?.let { cm.getNetworkCapabilities(it) }
            out["transport"] = when {
                caps == null -> "none"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                else -> "unknown"
            }
            if (out["transport"] == "wifi") {
                @Suppress("DEPRECATION")
                val wi = (ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager).connectionInfo
                if (wi != null && wi.rssi > -127 && wi.rssi < 0) out["rssi"] = wi.rssi
                if (wi != null && wi.linkSpeed > 0) out["linkMbps"] = wi.linkSpeed
            }
        } catch (_: Throwable) {
            out["transport"] = out["transport"] ?: "unknown"
        }
        return out
    }
}
