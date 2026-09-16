package br.com.log20.variavel

import java.net.URI

internal object DownloadRoutes {
    fun matches(location: String): Boolean = runCatching {
        val path = URI(location).path.orEmpty()
        Regex(".*\\.(xlsx?|csv|zip|docx?|pptx?|txt|ods|odt)$", RegexOption.IGNORE_CASE).matches(path) ||
            Regex("/checklists/[^/]+/(download_photos|export_excel)").matches(path) ||
            Regex("/invoices/[^/]+/download_document").matches(path) ||
            path.startsWith("/rails/active_storage/blobs/")
    }.getOrDefault(false)
}
