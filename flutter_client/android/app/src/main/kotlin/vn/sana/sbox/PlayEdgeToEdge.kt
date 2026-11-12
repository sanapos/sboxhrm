package vn.sana.sbox

import android.os.Build
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/**
 * Android 15 edge-to-edge without deprecated Window color / SHORT_EDGES APIs.
 *
 * Do not call androidx [androidx.activity.enableEdgeToEdge] — that helper still
 * contains setStatusBarColor, setNavigationBarColor, and
 * LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES, which Play flags in the DEX.
 */
fun ComponentActivity.applyPlayEdgeToEdge() {
    val window = window
    WindowCompat.setDecorFitsSystemWindows(window, false)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val attrs = window.attributes
        attrs.layoutInDisplayCutoutMode =
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        window.attributes = attrs
    }

    // SBOX POS, SBOX HRM (sbox.sana.vn*), Nhân Viên, BOSS: các thanh cùng màu nền sáng của app nên
    // icon hệ thống tối. KDS: thanh trắng như thanh đầu màn bếp (màn bếp tối thì Flutter đổi icon sáng).
    val lightBars = packageName.startsWith("sbox.sana.vn") || packageName.startsWith("staff.sboxpos.com") ||
        packageName.startsWith("boss.sboxpos.com") || packageName.startsWith("kds.sboxpos.com")
    fun darkSystemBarIcons() {
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = lightBars
            isAppearanceLightNavigationBars = lightBars
            // DEFAULT: thanh hệ thống giữ hiện. TRANSIENT_SWIPE khiến
            // status/nav ẩn sau immersive — phải vuốt mới hiện lại.
            systemBarsBehavior = if (hidesNavigationBar) {
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
            }
        }
    }
    darkSystemBarIcons()
    window.decorView.post { darkSystemBarIcons() }
    window.decorView.postDelayed({ darkSystemBarIcons() }, 400)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        window.isNavigationBarContrastEnforced = false
        window.isStatusBarContrastEnforced = false
    }
    hideNavigationBarIfHrm()
    window.decorView.post { hideNavigationBarIfHrm() }
}

/**
 * SBOX HRM (`sbox.sana.vn`) và SBOX POS (`sbox.sana.vn.pos`), kể cả gói .qa: luôn ẩn thanh điều
 * hướng cho rộng màn. BOSS / KDS / Nhân Viên giữ thanh.
 */
val ComponentActivity.hidesNavigationBar: Boolean
    get() = packageName in setOf("sbox.sana.vn", "sbox.sana.vn.qa", "sbox.sana.vn.pos", "sbox.sana.vn.pos.qa")

/**
 * Ẩn thanh điều hướng (giữ thanh trạng thái). Vuốt từ mép dưới lên: thanh hiện tạm, đè lên app
 * (không đẩy nội dung) rồi tự ẩn lại sau vài giây.
 *
 * Flutter đặt lại cờ hệ thống khi gọi SystemChrome và khi quay lại app (onPostResume) → gọi lại
 * ở onPostResume / onWindowFocusChanged và từ Dart sau khi thoát «Toàn màn hình».
 */
fun ComponentActivity.hideNavigationBarIfHrm() {
    if (!hidesNavigationBar) return
    WindowCompat.getInsetsController(window, window.decorView).apply {
        systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        hide(WindowInsetsCompat.Type.navigationBars())
    }
}
