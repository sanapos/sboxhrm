package vn.sana.sbox

import android.os.Build
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.core.view.WindowCompat
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

    fun darkSystemBarIcons() {
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
            // DEFAULT: thanh hệ thống giữ hiện. TRANSIENT_SWIPE khiến
            // status/nav ẩn sau immersive — phải vuốt mới hiện lại.
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
        }
    }
    darkSystemBarIcons()
    window.decorView.post { darkSystemBarIcons() }
    window.decorView.postDelayed({ darkSystemBarIcons() }, 400)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        window.isNavigationBarContrastEnforced = false
        window.isStatusBarContrastEnforced = false
    }
}
