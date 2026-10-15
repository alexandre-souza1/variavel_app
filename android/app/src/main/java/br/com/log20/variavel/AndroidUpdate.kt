package br.com.log20.variavel

import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import org.json.JSONObject

internal data class ApkIdentity(val applicationId: String, val versionCode: Long,
                                val versionName: String?, val signers: Set<String>)

internal data class AndroidUpdate(
    val versionCode: Long,
    val versionName: String,
    val notes: String,
    val sha256: String,
    val byteSize: Long,
    val apkUrl: String
) {
    fun verifyPackage(installed: ApkIdentity, candidate: ApkIdentity) {
        if (candidate.applicationId != installed.applicationId || candidate.versionCode != versionCode ||
            candidate.versionCode <= installed.versionCode || candidate.versionName != versionName) {
            throw IOException("O APK não corresponde à versão anunciada do Logia.")
        }
        if (installed.signers.isEmpty() || candidate.signers != installed.signers) {
            throw IOException("A assinatura desta atualização é diferente da instalação atual. Contate o administrador.")
        }
    }

    fun verifyFile(file: File) {
        if (file.length() != byteSize) throw IOException("O download ficou incompleto. Tente novamente.")
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (actual != sha256) throw IOException("Não foi possível verificar a atualização. Baixe novamente.")
    }

    companion object {
        const val MAX_BYTES = 150L * 1024 * 1024
    }
}

internal class AndroidUpdateClient(
    private val appUrl: String,
    private val applicationId: String,
    private val channel: String,
    private val cookieForUrl: (String) -> String?,
    private val connect: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection }
) {
    fun latest(): AndroidUpdate? {
        val location = appUrl.trimEnd('/') + "/mobile/android_release.json?channel=$channel"
        val connection = connect(URL(location)).apply {
            instanceFollowRedirects = false
            connectTimeout = 15_000
            readTimeout = 20_000
            setRequestProperty("Accept", "application/json")
            cookieForUrl(location)?.let { setRequestProperty("Cookie", it) }
        }
        try {
            if (connection.responseCode == 204) return null
            if (connection.responseCode in listOf(401, 403)) throw IOException("Entre novamente no aplicativo para verificar atualizações.")
            if (connection.responseCode != 200) throw IOException("Não foi possível consultar atualizações. Tente novamente mais tarde.")
            if (connection.contentType?.substringBefore(';')?.trim() != "application/json") {
                throw IOException("Entre no aplicativo e tente novamente.")
            }
            val body = connection.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > 65_536) throw IOException("Resposta de atualização inválida.")
                    output.write(buffer, 0, count)
                }
                output.toString("UTF-8")
            }
            return parse(JSONObject(body))
        } finally {
            connection.disconnect()
        }
    }

    private fun parse(json: JSONObject): AndroidUpdate {
        val path = json.getString("apk_path")
        require(json.getString("application_id") == applicationId && json.getString("channel") == channel &&
            Regex("/mobile/android_releases/[1-9][0-9]*/apk").matches(path)) { "Resposta de atualização inválida." }
        val update = AndroidUpdate(json.getLong("version_code"), json.getString("version_name"),
            json.optString("notes"), json.getString("sha256"), json.getLong("byte_size"),
            URI(appUrl).resolve(path).toString())
        require(update.versionCode in 1..2_100_000_000L && update.byteSize in 1..AndroidUpdate.MAX_BYTES &&
            update.versionName.isNotBlank() && update.versionName.length <= 50 && update.notes.length <= 4000 &&
            Regex("[0-9a-f]{64}").matches(update.sha256) && PdfDownload.sameOrigin(appUrl, update.apkUrl)) {
            "Resposta de atualização inválida."
        }
        return update
    }

    fun download(update: AndroidUpdate, destination: File, onProgress: (Long) -> Unit) {
        require(PdfDownload.sameOrigin(appUrl, update.apkUrl)) { "Endereço de atualização inválido." }
        try {
            PdfDownload(appUrl, cookieForUrl, connect).fetch(update.apkUrl, destination,
                requirePdf = false, maxBytes = update.byteSize, onProgress = onProgress)
            update.verifyFile(destination)
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }
}
