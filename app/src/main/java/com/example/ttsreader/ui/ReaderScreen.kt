package com.example.ttsreader.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.ttsreader.core.WordRange
import com.example.ttsreader.tts.TtsEngine

@Composable
fun ReaderScreen(
    viewModel: ReaderViewModel,
    incomingSharedText: String?,
    onOpenLibrary: () -> Unit,
    onUploadFile: () -> Unit
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    var audioMenuExpanded by remember { mutableStateOf(false) }
    var navigateMenuExpanded by remember { mutableStateOf(false) }
    var readerMenuExpanded by remember { mutableStateOf(false) }
    var optionsMenuExpanded by remember { mutableStateOf(false) }

    LaunchedEffect(incomingSharedText) {
        if (!incomingSharedText.isNullOrBlank()) {
            viewModel.importSharedText(incomingSharedText)
        }
    }

    val readerStyle = MaterialTheme.typography.bodyLarge.copy(
        fontSize = state.readerFontSizeSp.sp,
        lineHeight = (state.readerFontSizeSp * state.readerLineHeightMultiplier).sp
    )

    val pageText = state.pageTexts.getOrElse(state.selectedPageIndex) { "" }
    val pageStart = state.pageStartOffsets.getOrNull(state.selectedPageIndex)
        ?: 0
    val pageCount = state.pageTexts.size.coerceAtLeast(1)
    val chunkCount = state.chunks.size.coerceAtLeast(1)
    val nowPlayingText = if (state.isFocusPaused) {
        "Paused by another app"
    } else {
        "Ready"
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Lu Ji Reader", style = MaterialTheme.typography.headlineSmall)
            Text(
                text = state.selectedEngine.displayName,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold
            )
        }

        Surface(
            modifier = Modifier.fillMaxWidth(),
            tonalElevation = 2.dp,
            shape = MaterialTheme.shapes.medium
        ) {
            Text(
                text = state.status,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp)
            )
        }

        if (state.isFocusPaused) {
            Text(
                text = "Playback paused by another audio app (assistant/music).",
                color = MaterialTheme.colorScheme.error,
                fontWeight = FontWeight.Bold
            )
        }

        Surface(
            modifier = Modifier.fillMaxWidth(),
            tonalElevation = 3.dp,
            shape = MaterialTheme.shapes.medium
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 10.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "Now Reading",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Page ${state.selectedPageIndex + 1}/$pageCount • Chunk ${state.currentChunkIndex + 1}/$chunkCount",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Column(horizontalAlignment = androidx.compose.ui.Alignment.End) {
                    Text(
                        text = nowPlayingText,
                        style = MaterialTheme.typography.labelMedium,
                        color = if (state.isFocusPaused) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
                    )
                    Text(
                        text = "Saved ${state.lastSavedCharOffset}",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            TopMenu(
                label = "Play",
                expanded = audioMenuExpanded,
                onExpandedChange = { audioMenuExpanded = it }
            ) {
                DropdownMenuItem(text = { Text("Build Audio") }, onClick = {
                    audioMenuExpanded = false
                    viewModel.prepareAndSynthesize()
                })
                DropdownMenuItem(text = { Text("Play") }, onClick = {
                    audioMenuExpanded = false
                    viewModel.play()
                })
                DropdownMenuItem(text = { Text("Pause") }, onClick = {
                    audioMenuExpanded = false
                    viewModel.pause()
                })
                DropdownMenuItem(text = { Text("Play This Page") }, onClick = {
                    audioMenuExpanded = false
                    viewModel.playSelectedPage()
                })
                HorizontalDivider()
                DropdownMenuItem(text = { Text("Speed -") }, onClick = {
                    audioMenuExpanded = false
                    viewModel.setSpeed((state.playbackSpeed - 0.05f).coerceAtLeast(0.5f))
                })
                DropdownMenuItem(text = { Text("Speed +") }, onClick = {
                    audioMenuExpanded = false
                    viewModel.setSpeed((state.playbackSpeed + 0.05f).coerceAtMost(1.5f))
                })
            }

            TopMenu(
                label = "Nav",
                expanded = navigateMenuExpanded,
                onExpandedChange = { navigateMenuExpanded = it }
            ) {
                DropdownMenuItem(text = { Text("Previous Page") }, onClick = {
                    navigateMenuExpanded = false
                    viewModel.previousPage()
                })
                DropdownMenuItem(text = { Text("Next Page") }, onClick = {
                    navigateMenuExpanded = false
                    viewModel.nextPage()
                })
                DropdownMenuItem(
                    text = {
                        Text(
                            if (state.autoPlayOnPageChange) "Page buttons: Auto-play" else "Page buttons: Browse only"
                        )
                    },
                    onClick = {
                        navigateMenuExpanded = false
                        viewModel.setAutoPlayOnPageChange(!state.autoPlayOnPageChange)
                    }
                )
                HorizontalDivider()
                DropdownMenuItem(text = { Text("Open Library") }, onClick = {
                    navigateMenuExpanded = false
                    onOpenLibrary()
                })
            }

            TopMenu(
                label = "Text",
                expanded = readerMenuExpanded,
                onExpandedChange = { readerMenuExpanded = it }
            ) {
                DropdownMenuItem(text = { Text("Preset: Compact") }, onClick = {
                    readerMenuExpanded = false
                    viewModel.setReaderPreset("Compact")
                })
                DropdownMenuItem(text = { Text("Preset: Comfortable") }, onClick = {
                    readerMenuExpanded = false
                    viewModel.setReaderPreset("Comfortable")
                })
                DropdownMenuItem(text = { Text("Preset: Large") }, onClick = {
                    readerMenuExpanded = false
                    viewModel.setReaderPreset("Large")
                })
                HorizontalDivider()
                DropdownMenuItem(text = { Text("Font size -") }, onClick = {
                    readerMenuExpanded = false
                    viewModel.setReaderFontSize((state.readerFontSizeSp - 1f).coerceAtLeast(14f))
                })
                DropdownMenuItem(text = { Text("Font size +") }, onClick = {
                    readerMenuExpanded = false
                    viewModel.setReaderFontSize((state.readerFontSizeSp + 1f).coerceAtMost(26f))
                })
                DropdownMenuItem(text = { Text("Line height -") }, onClick = {
                    readerMenuExpanded = false
                    viewModel.setReaderLineHeight((state.readerLineHeightMultiplier - 0.05f).coerceAtLeast(1.1f))
                })
                DropdownMenuItem(text = { Text("Line height +") }, onClick = {
                    readerMenuExpanded = false
                    viewModel.setReaderLineHeight((state.readerLineHeightMultiplier + 0.05f).coerceAtMost(2.0f))
                })
            }

            TopMenu(
                label = "More",
                expanded = optionsMenuExpanded,
                onExpandedChange = { optionsMenuExpanded = it }
            ) {
                DropdownMenuItem(text = { Text("Engine: System") }, onClick = {
                    optionsMenuExpanded = false
                    viewModel.updateSelectedEngine(TtsEngine.SYSTEM)
                })
                DropdownMenuItem(text = { Text("Engine: Piper") }, onClick = {
                    optionsMenuExpanded = false
                    viewModel.updateSelectedEngine(TtsEngine.PIPER)
                })
                if (state.selectedEngine == TtsEngine.PIPER) {
                    HorizontalDivider()
                    state.availableVoices.forEach { voice ->
                        DropdownMenuItem(text = { Text("Voice: $voice") }, onClick = {
                            optionsMenuExpanded = false
                            viewModel.updateSelectedVoice(voice)
                        })
                    }
                }
                HorizontalDivider()
                DropdownMenuItem(text = { Text("Upload File") }, onClick = {
                    optionsMenuExpanded = false
                    onUploadFile()
                })
            }
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "Page ${state.selectedPageIndex + 1}/$pageCount • Speed ${"%.2f".format(state.playbackSpeed)}x",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = viewModel::previousPage) { Text("Prev") }
                    TextButton(onClick = viewModel::playSelectedPage) { Text("Play Page") }
                    TextButton(onClick = viewModel::nextPage) { Text("Next") }
                }
                Text(
                    text = "Tap any word below to mark it as the last read position.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "Blue = saved place. Amber = currently spoken word.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 360.dp, max = 560.dp)
                        .verticalScroll(rememberScrollState())
                ) {
                    if (pageText.isBlank()) {
                        Text(
                            text = "No page content yet. Upload text and Build Audio.",
                            style = readerStyle
                        )
                    } else {
                        ClickableText(
                            text = buildPageAnnotatedText(
                                pageText = pageText,
                                pageStart = pageStart,
                                activeWordRange = state.activeWordRange,
                                lastSavedCharOffset = state.lastSavedCharOffset
                            ),
                            style = readerStyle,
                            onClick = { localOffset ->
                                viewModel.markLastReadAtPageOffset(localOffset)
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TopMenu(
    label: String,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    content: @Composable () -> Unit
) {
    Box {
        FilledTonalButton(onClick = { onExpandedChange(true) }) {
            Text(label)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { onExpandedChange(false) }) {
            content()
        }
    }
}

private fun buildPageAnnotatedText(
    pageText: String,
    pageStart: Int,
    activeWordRange: WordRange?,
    lastSavedCharOffset: Int
): AnnotatedString {
    if (pageText.isBlank()) return AnnotatedString("")

    val activeStart = activeWordRange?.startOffset?.minus(pageStart)
        ?.coerceIn(0, pageText.length)
    val activeEnd = activeWordRange?.endOffset?.minus(pageStart)
        ?.coerceIn(activeStart ?: 0, pageText.length)

    val savedLocal = (lastSavedCharOffset - pageStart)
        .coerceIn(0, pageText.lastIndex.coerceAtLeast(0))
    val savedRange = pageText.wordRangeNearLocalOffset(savedLocal)

    return buildAnnotatedString {
        append(pageText)

        if (!savedRange.isEmpty() && savedRange.last + 1 <= pageText.length) {
            addStyle(
                style = SpanStyle(background = Color(0x3342A5F5), fontWeight = FontWeight.Medium),
                start = savedRange.first,
                end = savedRange.last + 1
            )
        }

        if (activeStart != null && activeEnd != null && activeEnd > activeStart) {
            addStyle(
                style = SpanStyle(background = Color(0x66FFC107), fontWeight = FontWeight.Bold),
                start = activeStart,
                end = activeEnd
            )
        }
    }
}

private fun String.wordRangeNearLocalOffset(targetLocalOffset: Int): IntRange {
    val words = Regex("\\S+").findAll(this).toList()
    if (words.isEmpty()) return IntRange.EMPTY

    val containing = words.firstOrNull { targetLocalOffset in it.range.first..it.range.last }
    val chosen = containing ?: words.lastOrNull { it.range.first <= targetLocalOffset } ?: words.first()
    return chosen.range
}
