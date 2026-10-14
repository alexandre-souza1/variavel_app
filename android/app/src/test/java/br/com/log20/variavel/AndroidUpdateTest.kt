package br.com.log20.variavel

import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AndroidUpdateTest {
    private val origin = "https://app.example/"
    private val body = "signed APK bytes"
    private val sha = MessageDigest.getInstance("SHA-256").digest(body.toByteArray())
        .joinToString("") { "%02x".format(it) }
    private val update = AndroidUpdate(9, "0.4.1", "Novidades", sha, body.length.toLong(), origin + "mobile/android_releases/1/apk")

    private class Response(url: URL, private val code: Int = 200, private val body: String,
                           private val mime: String = "application/json", private val redirect: String? = null) : HttpURLConnection(url) {
        override fun connect() {}
        override fun disconnect() {}
        override fun usingProxy() = false
        override fun getResponseCode() = code
        override fun getInputStream() = body.byteInputStream()
        override fun getContentType() = mime
        override fun getHeaderField(name: String) = if (name == "Location") redirect else null
    }

    private fun manifest() = JSONObject().put("application_id", "br.com.log20.variavel")
        .put("channel", "release").put("version_code", 9).put("version_name", "0.4.1")
        .put("notes", "Novidades").put("sha256", sha).put("byte_size", body.length)
        .put("apk_path", "/mobile/android_releases/1/apk")

    private fun client(response: Response) = AndroidUpdateClient(origin, "br.com.log20.variavel", "release", { "session=test" }, { response })

    private fun temporary(test: (File) -> Unit) {
        val file = File.createTempFile("update-test", ".apk")
        try { test(file) } finally { file.delete() }
    }

    @Test fun `manifest uses authentication and accepts the server contract`() {
        val response = Response(URL(origin), body = manifest().toString())
        assertEquals(update, client(response).latest())
        assertEquals("session=test", response.getRequestProperty("Cookie"))
        assertFalse(response.instanceFollowRedirects)
    }

    @Test fun `manifest rejects other packages channels external URLs and invalid bounds`() {
        val invalid = listOf(
            manifest().put("application_id", "other.app"), manifest().put("channel", "debug"),
            manifest().put("apk_path", "https://attacker.example/update.apk"),
            manifest().put("apk_path", "//attacker.example/update.apk"),
            manifest().put("byte_size", AndroidUpdate.MAX_BYTES + 1),
            manifest().put("version_code", 0), manifest().put("sha256", "forged")
        )
        invalid.forEach { json ->
            assertThrows(IllegalArgumentException::class.java) { client(Response(URL(origin), body = json.toString())).latest() }
        }
    }

    @Test fun `missing release does not prompt and auth failures do not follow redirects`() {
        assertNull(client(Response(URL(origin), code = 204, body = "")).latest())
        listOf(401, 403, 302, 500).forEach { code ->
            assertThrows(IOException::class.java) { client(Response(URL(origin), code = code, body = "")).latest() }
        }
        assertThrows(IOException::class.java) { client(Response(URL(origin), body = "<html>Login</html>", mime = "text/html")).latest() }
        assertThrows(IOException::class.java) { client(Response(URL(origin), body = "x".repeat(65_537))).latest() }
    }

    @Test fun `verified download reports progress and storage never receives the session`() = temporary { file ->
        val connections = mutableListOf<Response>()
        val client = AndroidUpdateClient(origin, "br.com.log20.variavel", "release", { "session=test" }) { url ->
            Response(url, code = if (connections.isEmpty()) 303 else 200, body = body,
                mime = "application/vnd.android.package-archive", redirect = "https://storage.example/update.apk")
                .also { connections.add(it) }
        }
        var received = 0L
        client.download(update, file) { received = it }
        assertEquals(body, file.readText())
        assertEquals(update.byteSize, received)
        assertEquals("session=test", connections[0].getRequestProperty("Cookie"))
        assertNull(connections[1].getRequestProperty("Cookie"))
    }

    @Test fun `tampered truncated oversized and insecure downloads are removed`() = temporary { file ->
        listOf(body.replace("signed", "forged"), body.dropLast(1), body + "extra").forEach { invalid ->
            val response = Response(URL(origin), body = invalid, mime = "application/octet-stream")
            assertThrows(IOException::class.java) { client(response).download(update, file) {} }
            assertFalse(file.exists())
        }
        val response = Response(URL(origin), code = 302, body = "", redirect = "http://storage.example/update.apk")
        assertThrows(IllegalArgumentException::class.java) { client(response).download(update, file) {} }
        assertFalse(file.exists())
    }

    @Test fun `installation requires the same package and signing key and a newer announced version`() {
        val installed = ApkIdentity("br.com.log20.variavel", 8, "0.4.0", setOf("permanent-signing-certificate"))
        val candidate = installed.copy(versionCode = 9, versionName = "0.4.1")
        update.verifyPackage(installed, candidate)
        listOf(
            candidate.copy(applicationId = "other.app"), candidate.copy(versionCode = 8),
            candidate.copy(versionCode = 10), candidate.copy(versionName = "other-version"),
            candidate.copy(signers = setOf("different-certificate")), candidate.copy(signers = emptySet())
        ).forEach { invalid ->
            assertThrows(IOException::class.java) { update.verifyPackage(installed, invalid) }
        }
        assertThrows(IOException::class.java) { update.verifyPackage(installed.copy(signers = emptySet()), candidate) }
        assertThrows(IOException::class.java) { update.verifyPackage(installed.copy(versionCode = 9), candidate) }
    }
}
