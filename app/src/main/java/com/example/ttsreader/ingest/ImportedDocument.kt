package com.example.ttsreader.ingest

import com.example.ttsreader.core.Page
import com.example.ttsreader.core.SourceType

data class ImportedDocument(
    val title: String,
    val sourceType: SourceType,
    val pages: List<Page>,
    val previewText: String
)
