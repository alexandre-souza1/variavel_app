package br.com.log20.variavel

import android.app.Application
import dev.hotwire.core.config.Hotwire
import dev.hotwire.navigation.config.defaultFragmentDestination
import dev.hotwire.navigation.config.registerFragmentDestinations
import dev.hotwire.navigation.config.registerRouteDecisionHandlers
import dev.hotwire.navigation.routing.AppNavigationRouteDecisionHandler
import dev.hotwire.navigation.routing.BrowserTabRouteDecisionHandler
import dev.hotwire.navigation.routing.SystemNavigationRouteDecisionHandler

class VariavelApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Hotwire.config.applicationUserAgentPrefix = "Workstation Android;"
        Hotwire.config.webViewDebuggingEnabled = BuildConfig.DEBUG
        Hotwire.defaultFragmentDestination = VariavelWebFragment::class
        Hotwire.registerFragmentDestinations(VariavelWebFragment::class)
        Hotwire.registerRouteDecisionHandlers(
            PdfRouteDecisionHandler(),
            DownloadRouteDecisionHandler(),
            AppNavigationRouteDecisionHandler(),
            BrowserTabRouteDecisionHandler(),
            SystemNavigationRouteDecisionHandler()
        )
        // Retain shared copies long enough for receiving apps, then remove stale files.
        java.util.concurrent.Executors.newSingleThreadExecutor().let { executor ->
            executor.execute {
                val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
                listOf("exports", "downloads").forEach { name ->
                    java.io.File(cacheDir, name).listFiles()?.filter { it.lastModified() < cutoff }
                        ?.forEach { it.deleteRecursively() }
                }
            }
            executor.shutdown()
        }
    }
}
