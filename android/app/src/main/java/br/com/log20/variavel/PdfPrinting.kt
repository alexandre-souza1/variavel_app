package br.com.log20.variavel

import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.Executors

object PdfPrinting {
    fun print(activity: AppCompatActivity, source: File) {
        activity.lifecycleScope.launch {
            try {
                val copy = withContext(Dispatchers.IO) {
                    source.copyTo(File.createTempFile("print-", ".pdf", activity.cacheDir), overwrite = true)
                }
                val worker = Executors.newSingleThreadExecutor()
                val adapter = object : PrintDocumentAdapter() {
                    override fun onLayout(oldAttributes: PrintAttributes?, newAttributes: PrintAttributes?,
                        cancellationSignal: CancellationSignal, callback: LayoutResultCallback, extras: Bundle?) {
                        if (cancellationSignal.isCanceled) callback.onLayoutCancelled()
                        else callback.onLayoutFinished(PrintDocumentInfo.Builder("relatorio.pdf")
                            .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                            .setPageCount(PrintDocumentInfo.PAGE_COUNT_UNKNOWN).build(), true)
                    }
                    override fun onWrite(pages: Array<out PageRange>, destination: ParcelFileDescriptor,
                        cancellationSignal: CancellationSignal, callback: WriteResultCallback) {
                        worker.execute {
                            try {
                                ParcelFileDescriptor.AutoCloseOutputStream(destination).use { output ->
                                    copy.inputStream().use { input ->
                                        val buffer = ByteArray(8192)
                                        while (!cancellationSignal.isCanceled) {
                                            val count = input.read(buffer)
                                            if (count < 0) break
                                            output.write(buffer, 0, count)
                                        }
                                    }
                                }
                                if (cancellationSignal.isCanceled) callback.onWriteCancelled()
                                else callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                            } catch (_: Exception) { callback.onWriteFailed(activity.getString(R.string.file_export_failed)) }
                        }
                    }
                    override fun onFinish() {
                        worker.execute { copy.delete() }
                        worker.shutdown()
                    }
                }
                activity.getSystemService(PrintManager::class.java).print("Workstation PDF", adapter, null)
            } catch (_: Exception) {
                android.widget.Toast.makeText(activity, R.string.file_export_failed, android.widget.Toast.LENGTH_LONG).show()
            }
        }
    }
}
