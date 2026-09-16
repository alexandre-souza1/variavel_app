package br.com.log20.variavel

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class PdfDownloadTest {
    private val origin = "https://app.example/"

    private class Response(url: URL, private val code: Int, private val body: String = "%PDF-1.4 test",
                           private val redirect: String? = null, private val mime: String = "application/pdf") : HttpURLConnection(url) {
        override fun connect() {}
        override fun disconnect() {}
        override fun usingProxy() = false
        override fun getResponseCode() = code
        override fun getContentType() = mime
        override fun getInputStream() = body.byteInputStream()
        override fun getHeaderField(name: String) = if (name == "Location") redirect else null
    }

    private fun temporary(test: (File) -> Unit) {
        val file = File.createTempFile("pdf-test", ".pdf")
        try { test(file) } finally { file.delete() }
    }

    @Test fun `authenticated report receives session cookie`() = temporary { file ->
        val response = Response(URL(origin), 200)
        PdfDownload(origin, { "session=secret" }, { response }).fetch(origin + "report.pdf", file)
        assertEquals("session=secret", response.getRequestProperty("Cookie"))
        assertTrue(file.readText().startsWith("%PDF-"))
    }

    @Test fun `redirect to storage does not receive Rails cookie`() = temporary { file ->
        val connections = mutableListOf<Response>()
        PdfDownload(origin, { "session=secret" }) { url ->
            Response(url, if (connections.isEmpty()) 302 else 200,
                redirect = "https://storage.example/report.pdf").also { connections.add(it) }
        }.fetch(origin + "report.pdf", file)
        assertEquals("session=secret", connections[0].getRequestProperty("Cookie"))
        assertNull(connections[1].getRequestProperty("Cookie"))
    }

    @Test fun `login HTML is rejected and temporary document removed`() = temporary { file ->
        val downloader = PdfDownload(origin, { null }) { Response(it, 200, "<html>Login</html>") }
        assertThrows(java.io.IOException::class.java) { downloader.fetch(origin + "report.pdf", file) }
        assertFalse(file.exists())
    }

    @Test fun `HTTP redirect is rejected`() = temporary { file ->
        val downloader = PdfDownload(origin, { null }) {
            Response(it, 302, redirect = "http://app.example/report.pdf")
        }
        assertThrows(IllegalArgumentException::class.java) { downloader.fetch(origin + "report.pdf", file) }
        assertFalse(file.exists())
    }

    @Test fun `redirect loop is bounded`() = temporary { file ->
        var requests = 0
        val downloader = PdfDownload(origin, { null }) {
            requests++
            Response(it, 302, redirect = "/report.pdf")
        }
        assertThrows(java.io.IOException::class.java) { downloader.fetch(origin + "report.pdf", file) }
        assertEquals(6, requests)
    }

    @Test fun `PDF routing handles query strings and origin includes port`() {
        assertTrue(PdfDownload.isPdf(origin + "report.PDF?download=true"))
        assertFalse(PdfDownload.isPdf(origin + "report?next=file.pdf"))
        assertTrue(PdfDownload.sameOrigin(origin, "https://app.example:443/report"))
        assertFalse(PdfDownload.sameOrigin(origin, "https://app.example:444/report"))
        assertFalse(PdfDownload.sameOrigin(origin, "https://app.example.attacker.test/report"))
    }

    @Test fun `generic download saves CSV with its MIME type`() = temporary { file ->
        val downloader = PdfDownload(origin, { "session=secret" }) {
            Response(it, 200, "name,value\nfoo,1\n", mime = "text/csv; charset=utf-8")
        }
        val metadata = downloader.fetch(origin + "export.csv", file, requirePdf = false)
        assertEquals("text/csv", metadata.mimeType)
        assertEquals("name,value\nfoo,1\n", file.readText())
    }

    @Test fun `generic download also rejects login HTML`() = temporary { file ->
        val downloader = PdfDownload(origin, { null }) {
            Response(it, 200, "<html>Login</html>", mime = "text/html; charset=utf-8")
        }
        assertThrows(java.io.IOException::class.java) {
            downloader.fetch(origin + "download", file, requirePdf = false)
        }
        assertFalse(file.exists())
    }

    @Test fun `unauthorized response removes the file`() = temporary { file ->
        val downloader = PdfDownload(origin, { null }) { Response(it, 403) }
        assertThrows(java.io.IOException::class.java) { downloader.fetch(origin + "export.zip", file, false) }
        assertFalse(file.exists())
    }

    @Test fun `download routes distinguish exports from web pages`() {
        assertTrue(DownloadRoutes.matches(origin + "reports/month.xlsx?unit=2"))
        assertTrue(DownloadRoutes.matches(origin + "checklists/42/download_photos"))
        assertTrue(DownloadRoutes.matches(origin + "invoices/42/download_document?document_id=2"))
        assertTrue(DownloadRoutes.matches(origin + "rails/active_storage/blobs/redirect/token/file.zip"))
        assertFalse(DownloadRoutes.matches(origin + "invoices/42"))
        assertFalse(DownloadRoutes.matches(origin + "downloads/42/open"))
        assertFalse(DownloadRoutes.matches(origin + "reports?search=file.xlsx"))
    }
}
