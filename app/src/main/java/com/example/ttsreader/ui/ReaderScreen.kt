package com.example.ttsreader.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.example.ttsreader.core.WordRange
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun ReaderScreen(viewModel: ReaderViewModel, incomingSharedText: String?) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var noteInput by remember { mutableStateOf("") }

    LaunchedEffect(incomingSharedText) {
        if (!incomingSharedText.isNullOrBlank()) {
            viewModel.importSharedText(incomingSharedText)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Android TTS.ai Reader", style = MaterialTheme.typography.headlineSmall)
        Text(state.status, style = MaterialTheme.typography.bodyMedium)
        state.cloudFallbackMessage?.let { msg ->
            Text(msg, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }

        OutlinedTextField(
            modifier = Modifier.fillMaxWidth(),
            value = state.title,
            onValueChange = viewModel::updateTitle,
            label = { Text("Title") }
        )

        OutlinedTextField(
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp),
            value = state.sourceText,
            onValueChange = viewModel::updateSourceText,
            label = { Text("Paste or edit source text") }
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = viewModel::prepareAndSynthesize) {
                Text("Build Audio")
            }
            Button(onClick = viewModel::play) { Text("Play") }
            Button(onClick = viewModel::pause) { Text("Pause") }
        }

        Text("Speed: ${"%.2f".format(state.playbackSpeed)}x")
        Slider(
            value = state.playbackSpeed,
            onValueChange = viewModel::setSpeed,
            valueRange = 0.7f..1.8f
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = viewModel::addBookmarkAtCurrentChunk) {
                Text("Bookmark Here")
            }
            Button(onClick = { viewModel.addNoteAtCurrentChunk(noteInput); noteInput = "" }) {
                Text("Add Note")
            }
        }

        OutlinedTextField(
            modifier = Modifier.fillMaxWidth(),
            value = noteInput,
            onValueChange = { noteInput = it },
            label = { Text("Note for current chunk") }
        )

        if (state.isLoading || state.isBuildingAudio) {
            if (state.buildProgressTotal > 0) {
                val fraction = (state.buildProgressCurrent.toFloat() / state.buildProgressTotal.toFloat())
                    .coerceIn(0f, 1f)
                LinearProgressIndicator(
                    progress = { fraction },
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    text = "${state.buildProgressCurrent}/${state.buildProgressTotal}",
                    style = MaterialTheme.typography.bodySmall
                )
            } else {
                CircularProgressIndicator(modifier = Modifier.width(28.dp))
            }
        }

        if (state.chapters.isNotEmpty()) {
            Text("Chapters: ${state.chapters.joinToString(", ")}", style = MaterialTheme.typography.bodySmall)
        }

        HorizontalDivider()
        Text("Follow Along", fontWeight = FontWeight.Bold)
        Text(
            text = buildHighlightedText(
                cleanedText = state.cleanedText,
                chunks = state.chunks,
                currentChunkIndex = state.currentChunkIndex,
                activeWordRange = state.activeWordRange
            )
        )

        HorizontalDivider()
        Text("Bookmarks (${state.bookmarks.size})", fontWeight = FontWeight.Bold)
        state.bookmarks.take(10).forEach {
            Text("Offset ${it.charOffset}")
        }

        HorizontalDivider()
        Text("Notes (${state.notes.size})", fontWeight = FontWeight.Bold)
        state.notes.take(10).forEach {
            Text("${it.startOffset}-${it.endOffset}: ${it.text}")
        }
    }
}

private fun buildHighlightedText(
    cleanedText: String,
    chunks: List<com.example.ttsreader.data.ChunkEntity>,
    currentChunkIndex: Int,
    activeWordRange: WordRange?
): AnnotatedString {
    if (cleanedText.isBlank()) return AnnotatedString("No cleaned text yet.")
    val chunk = chunks.getOrNull(currentChunkIndex) ?: return AnnotatedString(cleanedText)

    val start = chunk.startOffset.coerceAtLeast(0).coerceAtMost(cleanedText.length)
    val end = chunk.endOffset.coerceAtLeast(start).coerceAtMost(cleanedText.length)
    val wordStart = activeWordRange?.startOffset?.coerceIn(0, cleanedText.length)
    val wordEnd = activeWordRange?.endOffset?.coerceIn(wordStart ?: 0, cleanedText.length)

    return buildAnnotatedString {
        append(cleanedText)
        addStyle(
            style = SpanStyle(background = Color(0x33FFEB3B)),
            start = start,
            end = end
        )
        if (wordStart != null && wordEnd != null && wordEnd > wordStart) {
            addStyle(
                style = SpanStyle(background = Color(0xFFFFC107)),
                start = wordStart,
                end = wordEnd
            )
        }
    }
}
