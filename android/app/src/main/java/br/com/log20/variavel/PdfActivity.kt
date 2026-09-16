package br.com.log20.variavel

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.Gravity
import android.view.View
import android.webkit.CookieManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.HorizontalScrollView
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.graphics.createBitmap
import androidx.core.view.WindowInsetsCompat
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.min

class PdfActivity : AppCompatActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var document: File
    private lateinit var status: TextView
    private lateinit var preview: ImageView
    private lateinit var previous: Button
    private lateinit var next: Button
    private lateinit var retry: Button
    private lateinit var scroll: ScrollView
    private lateinit var save: Button
    private lateinit var share: Button
    private lateinit var print: Button
    private var zoom = 1f
    private var pageIndex = 0
    private var pageCount = 0
    private var bitmap: Bitmap? = null
    @Volatile private var closed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val actions = DocumentActions(this)
        zoom = savedInstanceState?.getFloat("zoom") ?: 1f
        pageIndex = savedInstanceState?.getInt("page") ?: 0
        document = File.createTempFile("report-", ".pdf", cacheDir)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        root.addView(Button(this).apply { setText(R.string.back); setOnClickListener { finish() } })
        status = TextView(this).apply { gravity = Gravity.CENTER; setText(R.string.opening_pdf) }
        root.addView(status)
        retry = Button(this).apply {
            setText(R.string.retry); visibility = View.GONE
            setOnClickListener { download() }
        }
        root.addView(retry)
        preview = ImageView(this).apply {
            adjustViewBounds = true
            contentDescription = getString(R.string.pdf_page)
            setBackgroundColor(Color.WHITE)
        }
        val horizontal = HorizontalScrollView(this).apply { addView(preview) }
        scroll = ScrollView(this).apply { addView(horizontal) }
        val exports = LinearLayout(this)
        save = Button(this).apply { setText(R.string.save_file); isEnabled = false
            setOnClickListener { actions.save(document, "application/pdf", "relatorio.pdf") } }
        share = Button(this).apply { setText(R.string.share_file); isEnabled = false
            setOnClickListener { actions.share(document, "application/pdf", "relatorio.pdf") } }
        print = Button(this).apply { setText(R.string.print_file); isEnabled = false
            setOnClickListener { PdfPrinting.print(this@PdfActivity, document) } }
        exports.addView(save, LinearLayout.LayoutParams(0, -2, 1f))
        exports.addView(share, LinearLayout.LayoutParams(0, -2, 1f))
        exports.addView(print, LinearLayout.LayoutParams(0, -2, 1f))
        root.addView(exports)
        val zoomControls = LinearLayout(this)
        fun changeZoom(amount: Float) {
            zoom = (zoom + amount).coerceIn(1f, 3f)
            preview.layoutParams = preview.layoutParams.apply {
                width = (resources.displayMetrics.widthPixels * zoom).toInt()
            }
        }
        zoomControls.addView(Button(this).apply { setText(R.string.zoom_out); setOnClickListener { changeZoom(-0.5f) } },
            LinearLayout.LayoutParams(0, -2, 1f))
        zoomControls.addView(Button(this).apply { setText(R.string.zoom_in); setOnClickListener { changeZoom(0.5f) } },
            LinearLayout.LayoutParams(0, -2, 1f))
        root.addView(zoomControls)
        changeZoom(0f)
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        val navigation = LinearLayout(this)
        previous = Button(this).apply { setText(R.string.previous); setOnClickListener { render(pageIndex - 1) } }
        next = Button(this).apply { setText(R.string.next); setOnClickListener { render(pageIndex + 1) } }
        navigation.addView(previous, LinearLayout.LayoutParams(0, -2, 1f))
        navigation.addView(next, LinearLayout.LayoutParams(0, -2, 1f))
        root.addView(navigation)
        setContentView(root)
        download()
    }

    private fun download() {
        setBusy()
        retry.visibility = View.GONE
        status.setText(R.string.opening_pdf)
        val location = intent.getStringExtra("url") ?: return finish()
        worker.execute {
            try {
                PdfDownload(BuildConfig.APP_URL, { CookieManager.getInstance().getCookie(it) })
                    .fetch(location, document)
                if (!closed) runOnUiThread { if (!closed) render(pageIndex) }
            } catch (error: Exception) {
                showError(error)
            }
        }
    }

    private fun render(index: Int) {
        setBusy()
        val targetWidth = (resources.displayMetrics.widthPixels * 2).coerceAtMost(2400)
        worker.execute {
            var rendered: Bitmap? = null
            try {
                ParcelFileDescriptor.open(document, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { renderer ->
                        pageCount = renderer.pageCount
                        check(pageCount > 0) { "O PDF não tem páginas." }
                        pageIndex = index.coerceIn(0, pageCount - 1)
                        renderer.openPage(pageIndex).use { page ->
                            val scale = min(targetWidth.toFloat() / page.width, 2400f / page.height)
                            rendered = createBitmap((page.width * scale).toInt().coerceAtLeast(1),
                                (page.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
                            rendered.eraseColor(Color.WHITE)
                            page.render(rendered, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        }
                    }
                }
                val result = rendered!!
                runOnUiThread {
                    if (closed) { result.recycle(); return@runOnUiThread }
                    preview.setImageBitmap(result)
                    bitmap?.recycle()
                    bitmap = result
                    scroll.scrollTo(0, 0)
                    status.text = getString(R.string.page_number, pageIndex + 1, pageCount)
                    save.isEnabled = true; share.isEnabled = true; print.isEnabled = true
                    previous.isEnabled = pageIndex > 0
                    next.isEnabled = pageIndex < pageCount - 1
                }
            } catch (error: Exception) {
                rendered?.recycle()
                showError(error)
            }
        }
    }

    private fun setBusy() { previous.isEnabled = false; next.isEnabled = false
        save.isEnabled = false; share.isEnabled = false; print.isEnabled = false }

    private fun showError(error: Exception) = runOnUiThread {
        if (!closed) {
            status.text = error.message ?: getString(R.string.pdf_error)
            retry.visibility = View.VISIBLE
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putInt("page", pageIndex)
        outState.putFloat("zoom", zoom)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        closed = true
        // Cleanup runs after pending work so the file is never removed during rendering.
        worker.execute { document.delete() }
        worker.shutdown()
        preview.setImageDrawable(null)
        bitmap?.recycle()
        super.onDestroy()
    }

    companion object {
        fun open(context: Context, url: String) {
            context.startActivity(Intent(context, PdfActivity::class.java).putExtra("url", url))
        }
    }
}
