package pl.synergialite.synergia_lite

import android.webkit.CookieManager
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Odczyt ciasteczek Synergii z magazynu WebView (wspólnego z webview_flutter).
 * Kanał zwraca dane wyłącznie dla synergia.librus.pl i niczego nie loguje.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSynergiaCookies" -> result.success(synergiaCookies())
                    "flush" -> {
                        CookieManager.getInstance().flush()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Każdy element: `name=value` + atrybuty (Domain, Path, Secure, HttpOnly, Expires…), jeśli WebView je udostępnia. */
    private fun synergiaCookies(): List<String> {
        val manager = CookieManager.getInstance()
        if (WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)) {
            return CookieManagerCompat.getCookieInfo(manager, SYNERGIA_ORIGIN)
        }
        return manager.getCookie(SYNERGIA_ORIGIN)
            ?.split(";")
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?: emptyList()
    }

    private companion object {
        const val CHANNEL = "pl.synergialite/cookies"
        const val SYNERGIA_ORIGIN = "https://synergia.librus.pl/"
    }
}
