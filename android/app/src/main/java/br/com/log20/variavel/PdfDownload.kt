package br.com.log20.variavel

import java.io.File
import java.io.IOException
import java.io.DataInputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

internal class PdfDownload(
    private val appUrl: String,
    private val cookieForUrl: (String) -> String?,
    private val connect: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection }
) {
    data class Metadata(val mimeType: String, val disposition: String?)

    fun fetch(location: String, destination: File, requirePdf: Boolean = true): Metadata {
        try {
            var current = URI(location)
            repeat(6) {
                require(current.scheme == "https" && current.host != null && current.userInfo == null) {
                    "O arquivo precisa estar em um endereço HTTPS."
                }
                val connection = connect(current.toURL()).apply {
                    instanceFollowRedirects = false
                    connectTimeout = 20_000
                    readTimeout = 30_000
                    setRequestProperty("Accept", if (requirePdf) "application/pdf" else "*/*")
                    // Never forward the Rails session to storage/CDN redirects.
                    if (sameOrigin(appUrl, current.toString())) {
                        cookieForUrl(current.toString())?.let { setRequestProperty("Cookie", it) }
                    }
                }
                try {
                    val status = connection.responseCode
                    if (status in listOf(301, 302, 303, 307, 308)) {
                        current = current.resolve(connection.getHeaderField("Location")
                            ?: throw IOException("Redirecionamento sem destino."))
                    } else {
                        if (status == 401 || status == 403) throw IOException("Entre novamente no aplicativo para abrir este arquivo.")
                        if (status != 200) throw IOException("Não foi possível baixar o arquivo (HTTP $status).")
                        connection.inputStream.use { input ->
                            destination.outputStream().use { output ->
                                val buffer = ByteArray(8192)
                                var total = 0L
                                while (true) {
                                    if (Thread.currentThread().isInterrupted) throw IOException("Download cancelado.")
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    total += count
                                    if (total > 50L * 1024 * 1024) throw IOException("O arquivo ultrapassa o limite de 50 MB.")
                                    output.write(buffer, 0, count)
                                }
                            }
                        }
                        val mime = connection.contentType?.substringBefore(';')?.trim()?.lowercase() ?: "application/octet-stream"
                        if (mime == "text/html" || mime == "application/xhtml+xml") {
                            throw IOException("O servidor retornou uma página de acesso. Entre novamente e tente baixar o arquivo.")
                        }
                        if (requirePdf) {
                        val header = ByteArray(5)
                        DataInputStream(destination.inputStream()).use { it.readFully(header) }
                        if (!header.contentEquals("%PDF-".toByteArray(Charsets.US_ASCII))) {
                            throw IOException("O servidor não retornou um PDF. Verifique sua sessão e tente novamente.")
                        }
                        }
                        return Metadata(if (requirePdf) "application/pdf" else mime, connection.getHeaderField("Content-Disposition"))
                    }
                } finally {
                    connection.disconnect()
                }
            }
            throw IOException("O arquivo teve redirecionamentos demais.")
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }

    companion object {
        fun sameOrigin(first: String, second: String): Boolean = runCatching {
            val a = URI(first)
            val b = URI(second)
            fun port(uri: URI) = if (uri.port == -1) 443 else uri.port
            a.scheme == "https" && b.scheme == "https" &&
                a.host.equals(b.host, ignoreCase = true) && port(a) == port(b)
        }.getOrDefault(false)

        fun isPdf(location: String): Boolean = runCatching {
            URI(location).path?.endsWith(".pdf", ignoreCase = true) == true
        }.getOrDefault(false)
    }
}
