package br.com.log20.variavel

import android.Manifest
import android.app.NotificationManager
import android.os.Build
import android.webkit.WebView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationManagerCompat
import androidx.fragment.app.Fragment
import com.google.firebase.messaging.FirebaseMessaging
import org.json.JSONObject
import org.json.JSONTokener

/** Registers through the authenticated WebView, with Rails' CSRF token. No JS bridge is exposed. */
class PushRegistration(private val fragment: Fragment) {
    private var currentWebView: WebView? = null
    private val permission = fragment.registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        currentWebView?.let { sync(it) }
    }

    fun sync(webView: WebView) {
        currentWebView = webView
        if (!PdfDownload.sameOrigin(BuildConfig.APP_URL, webView.url.orEmpty())) return
        webView.evaluateJavascript("document.body?.dataset.userId || 'guest'") { encoded ->
            val context = fragment.context ?: return@evaluateJavascript
            val user = runCatching { JSONTokener(encoded).nextValue() as? String }.getOrNull() ?: return@evaluateJavascript
            val preferences = context.getSharedPreferences("push", 0)
            if (user != preferences.getString("user", null)) {
                context.getSystemService(NotificationManager::class.java).cancelAll()
            }
            if (!user.matches(Regex("[1-9][0-9]*"))) {
                preferences.edit().remove("user").apply()
                return@evaluateJavascript
            }
            preferences.edit().putString("user", user).apply()
            (fragment.activity as? MainActivity)?.openPendingNotification(user)
            if (Build.VERSION.SDK_INT >= 33 && !preferences.getBoolean("permission_asked", false)) {
                preferences.edit().putBoolean("permission_asked", true).apply()
                permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                return@evaluateJavascript
            }
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                register(webView, user, null)
                return@evaluateJavascript
            }
            FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
                if (fragment.isAdded && preferences.getString("user", null) == user) register(webView, user, token)
            }
        }
    }

    private fun register(webView: WebView, user: String, token: String?) {
        val origin = JSONObject.quote(java.net.URI(BuildConfig.APP_URL).let {
            "${it.scheme}://${it.rawAuthority}"
        })
        val expectedUser = JSONObject.quote(user)
        val body = JSONObject().put("token", token).toString()
        val method = if (token == null) "DELETE" else "POST"
        webView.evaluateJavascript("""
            (() => {
              if (location.origin !== $origin || document.body?.dataset.userId !== $expectedUser) return;
              const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
              if (!csrf) return;
              fetch('/mobile/push_device', {
                method: '$method', credentials: 'same-origin', redirect: 'error',
                headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'X-CSRF-Token': csrf},
                body: ${JSONObject.quote(body)}
              }).catch(() => {});
            })();
        """.trimIndent(), null)
    }
}
