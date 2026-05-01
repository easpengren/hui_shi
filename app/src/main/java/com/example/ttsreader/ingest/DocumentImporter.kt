package com.example.ttsreader.ingest

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.example.ttsreader.core.Page
import com.example.ttsreader.core.SourceType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class DocumentImporter(
    private val context: Context,
    private val pdfExtractor: PdfExtractor = PdfExtractor(context),
    private val epubExtractor: EpubExtractor = EpubExtractor()
) {
    suspend fun import(uri: Uri): ImportedDocument = withContext(Dispatchers.IO) {
        val displayName = queryDisplayName(uri) ?: "Imported Document"
        val mimeType = context.contentResolver.getType(uri).orEmpty()
        val extension = displayName.substringAfterLast('.', missingDelimiterValue = "").lowercase()

        when {
            mimeType == "application/pdf" || extension == "pdf" -> {
                withContext(Dispatchers.Default) {
                    pdfExtractor.extract(context, uri, displayName).copy(
                        sourceUri = uri.toString(),
                        sourceDisplayName = displayName
                    )
                }
            }

            mimeType == "application/epub+zip" || extension == "epub" -> {
                withContext(Dispatchers.Default) {
                    epubExtractor.extract(context, uri, displayName).copy(
                        sourceUri = uri.toString(),
                        sourceDisplayName = displayName
                    )
                }
            }

            else -> importPlainText(uri, displayName)
        }
    }

    private fun importPlainText(uri: Uri, displayName: String): ImportedDocument {
        val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }.orEmpty()
        val lines = text.lines().ifEmpty { listOf("") }
        val pages = lines.chunked(40).mapIndexed { index, pageLines ->
            Page(index = index, lines = pageLines)
        }
        return ImportedDocument(
            title = displayName.substringBeforeLast('.'),
            sourceType = SourceType.PLAIN_TEXT,
            pages = pages,
            previewText = text,
            sourceUri = uri.toString(),
            sourceDisplayName = displayName
        )
    }

    private fun queryDisplayName(uri: Uri): String? {
        return context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
        }
    }
}
