package vn.sana.sbox

import android.content.Context
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import java.net.Inet4Address

/**
 * Hỗ trợ dò / đổi IP máy in LAN bằng UDP broadcast (Dart: pos_lan_printer_netconfig.dart):
 * giữ MulticastLock để Wi‑Fi không lọc gói broadcast, và đọc IP / prefix / gateway của máy.
 */
object LanPrinterNet {
    const val CHANNEL = "sbox/lan_printer_net"
    private var lock: WifiManager.MulticastLock? = null

    @Synchronized
    fun multicastLock(ctx: Context, on: Boolean) {
        try {
            if (on) {
                if (lock?.isHeld == true) return
                val wm = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                lock = wm.createMulticastLock("sbox-lan-printer").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            } else {
                lock?.let { if (it.isHeld) it.release() }
                lock = null
            }
        } catch (_: Throwable) {
        }
    }

    fun links(ctx: Context): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        try {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            @Suppress("DEPRECATION")
            for (n in cm.allNetworks) {
                val lp = cm.getLinkProperties(n) ?: continue
                val gw = lp.routes.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
                    ?.gateway?.hostAddress
                for (la in lp.linkAddresses) {
                    val a = la.address as? Inet4Address ?: continue
                    if (a.isLoopbackAddress || a.isLinkLocalAddress) continue
                    out.add(mapOf("ip" to a.hostAddress, "prefix" to la.prefixLength, "gateway" to gw))
                }
            }
        } catch (_: Throwable) {
        }
        return out
    }
}
