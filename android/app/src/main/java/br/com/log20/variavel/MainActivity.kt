package br.com.log20.variavel

import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

class MainActivity : HotwireActivity() {
    private fun notificationLocation(intent: android.content.Intent): String? {
        val id = intent.getStringExtra("notification_id") ?: return null
        val user = getSharedPreferences("push", 0).getString("user", null) ?: return null
        if (intent.getStringExtra("notification_user") != user || !id.matches(Regex("[1-9][0-9]*"))) return null
        return BuildConfig.APP_URL.trimEnd('/') + "/mobile/notifications/$id"
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val webView = delegate.currentNavigator?.session?.webView ?: return
        if (!PdfDownload.sameOrigin(BuildConfig.APP_URL, webView.url.orEmpty())) return
        webView.evaluateJavascript("document.body?.dataset.userId || 'guest'") { encoded ->
            val user = runCatching { org.json.JSONTokener(encoded).nextValue() as? String }.getOrNull()
            if (user != null) openPendingNotification(user)
        }
    }

    fun openPendingNotification(user: String) {
        if (intent.getStringExtra("notification_user") != user) return
        val location = notificationLocation(intent) ?: return
        val navigator = delegate.currentNavigator ?: return
        intent.removeExtra("notification_id")
        intent.removeExtra("notification_user")
        navigator.route(location)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val host = findViewById<View>(R.id.main_nav_host)
        ViewCompat.setOnApplyWindowInsetsListener(host) { view, insets ->
            val safeArea = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout() or
                    WindowInsetsCompat.Type.ime()
            )
            view.setPadding(safeArea.left, safeArea.top, safeArea.right, safeArea.bottom)
            // This container owns the safe area; children must not add it a second time.
            WindowInsetsCompat.CONSUMED
        }
        ViewCompat.requestApplyInsets(host)
    }

    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration(
            name = "main",
            // Load the authenticated web shell before routing, including PDF notifications.
            startLocation = BuildConfig.APP_URL,
            navigatorHostId = R.id.main_nav_host
        )
    )
}
