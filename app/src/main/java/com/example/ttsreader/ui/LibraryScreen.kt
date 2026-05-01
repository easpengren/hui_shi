package com.example.ttsreader.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun LibraryScreen(
    viewModel: ReaderViewModel,
    onBackToReader: () -> Unit,
    onOpenBook: (String) -> Unit
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Library", style = MaterialTheme.typography.headlineSmall)
            TextButton(onClick = onBackToReader) { Text("Back to Reader") }
        }

        if (state.libraryBooks.isEmpty()) {
            Text("No books yet. Import a file on the Reader screen.")
            return
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(state.libraryBooks, key = { it.id }) { book ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(book.title, fontWeight = FontWeight.Bold)
                        val sourceState = if (book.sourceAvailable) "on device" else "missing"
                        Text(
                            text = "${book.sourceDisplayName ?: "Unknown source"} • $sourceState",
                            style = MaterialTheme.typography.bodySmall
                        )
                        HorizontalDivider()
                        Text(
                            text = "Last page ${book.lastPageIndex + 1} • Saved offset ${book.lastCharOffset}",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Text(
                            text = "Chunks ${book.chunkCount}",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Button(onClick = { onOpenBook(book.id) }) {
                            Text("Open")
                        }
                    }
                }
            }
        }
    }
}
