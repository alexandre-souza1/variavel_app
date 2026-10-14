package br.com.log20.variavel

import android.app.Application
import android.content.pm.PackageManager
import android.webkit.CookieManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal sealed interface AppUpdateState {
    data object Checking : AppUpdateState
    data object Current : AppUpdateState
    data class Available(val update: AndroidUpdate) : AppUpdateState
    data class Downloading(val update: AndroidUpdate, val percent: Int) : AppUpdateState
    data class Ready(val update: AndroidUpdate, val file: File) : AppUpdateState
    data class Failed(val message: String) : AppUpdateState
}

internal class AppUpdateViewModel(application: Application) : AndroidViewModel(application) {
    private val mutableState = MutableStateFlow<AppUpdateState>(AppUpdateState.Checking)
    val state = mutableState.asStateFlow()
    private val client = AndroidUpdateClient(BuildConfig.APP_URL, BuildConfig.APPLICATION_ID,
        if (BuildConfig.DEBUG) "debug" else "release", { CookieManager.getInstance().getCookie(it) })

    init { check() }

    fun check() {
        mutableState.value = AppUpdateState.Checking
        viewModelScope.launch {
            try {
                val update = withContext(Dispatchers.IO) { client.latest() }
                mutableState.value = if (update == null || update.versionCode <= BuildConfig.VERSION_CODE) {
                    AppUpdateState.Current
                } else AppUpdateState.Available(update)
            } catch (error: CancellationException) { throw error
            } catch (error: Exception) {
                mutableState.value = AppUpdateState.Failed(error.message ?: "Não foi possível consultar atualizações.")
            }
        }
    }

    fun download() {
        val update = (mutableState.value as? AppUpdateState.Available)?.update ?: return
        mutableState.value = AppUpdateState.Downloading(update, 0)
        viewModelScope.launch {
            try {
                val file = withContext(Dispatchers.IO) {
                    val folder = File(getApplication<Application>().cacheDir, "updates/${UUID.randomUUID()}")
                    check(folder.mkdirs())
                    val destination = File(folder, "log-ia.apk")
                    try {
                        client.download(update, destination) { bytes ->
                            ensureActive()
                            mutableState.value = AppUpdateState.Downloading(update, (bytes * 100 / update.byteSize).toInt())
                        }
                        ensureActive()
                        verifyPackage(update, destination)
                        destination
                    } catch (error: Exception) {
                        destination.delete()
                        throw error
                    }
                }
                mutableState.value = AppUpdateState.Ready(update, file)
            } catch (error: CancellationException) { throw error
            } catch (error: Exception) {
                mutableState.value = AppUpdateState.Failed(error.message ?: "Não foi possível baixar a atualização.")
            }
        }
    }

    private fun verifyPackage(update: AndroidUpdate, file: File) {
        val context = getApplication<Application>()
        val manager = context.packageManager
        @Suppress("DEPRECATION")
        val candidate = manager.getPackageArchiveInfo(file.absolutePath, PackageManager.GET_SIGNING_CERTIFICATES)
            ?: throw IOException("O arquivo recebido não é um APK válido.")
        @Suppress("DEPRECATION")
        val installed = manager.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        fun identity(info: android.content.pm.PackageInfo) = ApkIdentity(info.packageName, info.longVersionCode,
            info.versionName, info.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet().orEmpty())
        update.verifyPackage(identity(installed), identity(candidate))
    }
}
