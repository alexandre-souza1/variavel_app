package br.com.log20.variavel

import android.content.ClipData
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/** Shares only an explicit copy; neither session cookies nor URLs leave the app. */
class DocumentActions(private val activity: AppCompatActivity) {
    private var pending: String? = activity.savedStateRegistry
        .consumeRestoredStateForKey("document-export")?.getString("source")
    private val savePicker = activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val source = pending?.let(::File)
        pending = null
        val target = result.data?.data
        if (result.resultCode == AppCompatActivity.RESULT_OK && source != null && target != null) {
            activity.lifecycleScope.launch {
                try {
                    withContext(Dispatchers.IO) {
                        activity.contentResolver.openOutputStream(target, "w")?.use { output ->
                            source.inputStream().use { it.copyTo(output) }
                        } ?: error(activity.getString(R.string.file_save_failed))
                    }
                    message(R.string.file_saved)
                } catch (_: Exception) { message(R.string.file_save_failed) }
            }
        }
    }

    init {
        activity.savedStateRegistry.registerSavedStateProvider("document-export") {
            Bundle().apply { putString("source", pending) }
        }
    }

    fun save(file: File, mime: String, name: String) = prepare(file, name) { copy ->
        pending = copy.absolutePath
        savePicker.launch(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, copy.name)
        })
    }

    fun share(file: File, mime: String, name: String) = prepare(file, name) { copy ->
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.exports", copy)
        activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newUri(activity.contentResolver, copy.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }, activity.getString(R.string.share_file)))
    }

    private fun prepare(file: File, name: String, action: (File) -> Unit) {
        activity.lifecycleScope.launch {
            try {
                val copy = withContext(Dispatchers.IO) {
                    val folder = File(activity.cacheDir, "exports/${UUID.randomUUID()}")
                    check(folder.mkdirs())
                    val safeName = name.substringAfterLast('/').substringAfterLast('\\')
                        .replace(Regex("[\\p{Cntrl}]"), "_").take(160).ifBlank { "arquivo" }
                    file.copyTo(File(folder, safeName))
                }
                action(copy)
            } catch (_: Exception) { message(R.string.file_export_failed) }
        }
    }

    private fun message(id: Int) = Toast.makeText(activity, id, Toast.LENGTH_LONG).show()
}

class ExportFileProvider : FileProvider()
