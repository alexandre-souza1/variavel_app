package br.com.log20.variavel

import android.webkit.CookieManager
import android.webkit.WebView
import androidx.appcompat.app.AlertDialog
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONTokener

internal class AppUpdatePrompt(private val activity: MainActivity) {
    private var checking = false
    private var nextAttemptAt = 0L
    private var dialog: AlertDialog? = null

    fun check(webView: WebView) {
        if (checking || System.currentTimeMillis() < nextAttemptAt || dialog?.isShowing == true ||
            !PdfDownload.sameOrigin(BuildConfig.APP_URL, webView.url.orEmpty())) return
        webView.evaluateJavascript("document.body?.dataset.userId || 'guest'") { encoded ->
            val user = runCatching { JSONTokener(encoded).nextValue() as? String }.getOrNull() ?: return@evaluateJavascript
            if (!user.matches(Regex("[1-9][0-9]*")) || checking) return@evaluateJavascript
            val preferences = activity.getSharedPreferences("app-updates", 0)
            val key = "checked-${BuildConfig.VERSION_CODE}-$user"
            val elapsed = System.currentTimeMillis() - preferences.getLong(key, 0)
            if (elapsed in 0 until 6 * 60 * 60 * 1000L) return@evaluateJavascript
            checking = true
            nextAttemptAt = System.currentTimeMillis() + 5 * 60 * 1000L
            activity.lifecycleScope.launch {
                try {
                    val update = withContext(Dispatchers.IO) {
                        AndroidUpdateClient(BuildConfig.APP_URL, BuildConfig.APPLICATION_ID,
                            if (BuildConfig.DEBUG) "debug" else "release", { CookieManager.getInstance().getCookie(it) }).latest()
                    }
                    preferences.edit().putLong(key, System.currentTimeMillis()).apply()
                    if (update != null && update.versionCode > BuildConfig.VERSION_CODE &&
                        activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) &&
                        PdfDownload.sameOrigin(BuildConfig.APP_URL, webView.url.orEmpty())) {
                        webView.evaluateJavascript("document.body?.dataset.userId || 'guest'") { current ->
                            val currentUser = runCatching { JSONTokener(current).nextValue() as? String }.getOrNull()
                            if (currentUser != user || !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return@evaluateJavascript
                            dialog = AlertDialog.Builder(activity)
                                .setTitle(R.string.update_title)
                                .setMessage(activity.getString(R.string.update_available, update.versionName))
                                .setPositiveButton(R.string.update_download) { _, _ -> AppUpdateActivity.open(activity) }
                                .setNegativeButton(R.string.update_later, null)
                                .show()
                        }
                    }
                } catch (error: CancellationException) { throw error
                } catch (_: Exception) {
                    // Network or session failures must never interrupt normal app use.
                } finally { checking = false }
            }
        }
    }
}
