package com.example.ttsreader

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.example.ttsreader.ingest.DocumentImporter
import com.example.ttsreader.ui.LibraryScreen
import com.example.ttsreader.ui.ReaderScreen
import com.example.ttsreader.ui.ReaderViewModel
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private enum class AppScreen { READER, LIBRARY }

    private val viewModel by viewModels<ReaderViewModel>()
    private lateinit var documentImporter: DocumentImporter

    private val openDocumentLauncher = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri != null) {
            runCatching {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
            lifecycleScope.launch {
                runCatching {
                    documentImporter.import(uri)
                }.onSuccess { doc ->
                    viewModel.importDocument(doc)
                }.onFailure { err ->
                    viewModel.setStatus("Import failed: ${err.message ?: err::class.java.simpleName}")
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        documentImporter = DocumentImporter(this)

        val sharedText = extractSharedText(intent)
        importSharedDocument(intent)

        setContent {
            var currentScreen by rememberSaveable { mutableStateOf(AppScreen.READER) }

            MaterialTheme {
                Surface {
                    Column(
                        modifier = Modifier
                            .statusBarsPadding()
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        when (currentScreen) {
                            AppScreen.READER -> ReaderScreen(
                                viewModel = viewModel,
                                incomingSharedText = sharedText,
                                onOpenLibrary = { currentScreen = AppScreen.LIBRARY },
                                onUploadFile = {
                                    openDocumentLauncher.launch(
                                        arrayOf("application/pdf", "application/epub+zip", "text/plain", "*/*")
                                    )
                                }
                            )

                            AppScreen.LIBRARY -> LibraryScreen(
                                viewModel = viewModel,
                                onBackToReader = { currentScreen = AppScreen.READER },
                                onOpenBook = { bookId ->
                                    viewModel.openLibraryBook(bookId)
                                    currentScreen = AppScreen.READER
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_SEND_MULTIPLE -> {
                val list = intent.getStringArrayListExtra(Intent.EXTRA_TEXT)
                list?.joinToString("\n")
            }
            else -> null
        }
    }

    private fun importSharedDocument(intent: Intent?) {
        val uri = when (intent?.action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else -> null
        } ?: return

        lifecycleScope.launch {
            runCatching {
                viewModel.importDocument(documentImporter.import(uri))
            }
        }
    }
}
