package br.com.log20.variavel

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.URLUtil
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class DownloadActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val actions = DocumentActions(this)
        val location = intent.getStringExtra("url") ?: return finish()
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left + 24, bars.top + 24, bars.right + 24, bars.bottom + 24)
            insets
        }
        root.addView(Button(this).apply { setText(R.string.back); setOnClickListener { finish() } })
        val status = TextView(this).apply { setText(R.string.downloading) }
        root.addView(status)
        val retry = Button(this).apply { setText(R.string.retry); visibility = android.view.View.GONE }
        root.addView(retry)
        val save = Button(this).apply { setText(R.string.save_file); isEnabled = false }
        val share = Button(this).apply { setText(R.string.share_file); isEnabled = false }
        root.addView(save); root.addView(share)
        setContentView(root)
        fun download() {
            retry.visibility = android.view.View.GONE
            status.setText(R.string.downloading)
            lifecycleScope.launch {
                try {
                    val (file, metadata) = withContext(Dispatchers.IO) {
                        val folder = File(cacheDir, "downloads").apply { mkdirs() }
                        val file = File.createTempFile("download-", ".bin", folder)
                        file to PdfDownload(BuildConfig.APP_URL, { CookieManager.getInstance().getCookie(it) })
                            .fetch(location, file, requirePdf = false)
                    }
                    val name = URLUtil.guessFileName(location, metadata.disposition, metadata.mimeType)
                    status.text = name
                    save.isEnabled = true; share.isEnabled = true
                    save.setOnClickListener { actions.save(file, metadata.mimeType, name) }
                    share.setOnClickListener { actions.share(file, metadata.mimeType, name) }
                } catch (error: Exception) {
                    status.text = error.message ?: getString(R.string.download_failed)
                    retry.visibility = android.view.View.VISIBLE
                }
            }
        }
        retry.setOnClickListener { download() }
        download()
    }
    companion object {
        fun open(context: Context, url: String) = context.startActivity(
            Intent(context, DownloadActivity::class.java).putExtra("url", url))
    }
}
