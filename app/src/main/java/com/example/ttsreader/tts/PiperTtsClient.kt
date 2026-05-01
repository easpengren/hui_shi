package com.example.ttsreader.tts

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.util.Log
import com.example.ttsreader.core.Chunk
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

class PiperTtsClient(
    context: Context,
    private val cacheManager: CacheManager,
    private val getVoice: () -> String = { DEFAULT_VOICE },
    private val getSpeed: () -> Float = { 1.0f }
) : TtsClient {

    private val appContext = context.applicationContext
    private val modelsDir = File(appContext.filesDir, "piper_models").apply { mkdirs() }
    private val stagingDir = File(
        appContext.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: appContext.cacheDir,
        "piper_models"
    ).apply { mkdirs() }
    private val downloadManager =
        appContext.getSystemService(DownloadManager::class.java)
            ?: error("DownloadManager is unavailable")

    private val engineLock = Mutex()
    private val manifestLock = Mutex()
    private var currentVoice: String? = null
    private var tts: OfflineTts? = null
    private var voicesManifest: JSONObject? = null

    override suspend fun synthesizeChunk(bookId: String, chunk: Chunk): File =
        withContext(Dispatchers.IO) {
            val output = cacheManager.pathFor(bookId, chunk.index, "wav")
            if (output.exists() && output.length() > 0L) {
                Log.i(TAG, "Using cached audio chunk ${chunk.index} for book $bookId")
                return@withContext output
            }
            if (output.exists()) output.delete()
            output.parentFile?.mkdirs()

            val voice = getVoice()
            val engine = ensureEngine(voice)
            val text = sanitizeTtsText(chunk.ttsText)
            Log.i(TAG, "Synthesizing fresh audio chunk ${chunk.index} for book $bookId with voice $voice")
            val result = engine.generate(text = text, sid = 0, speed = getSpeed())
            writePcmWav(output, result.samples, result.sampleRate)
            output
        }

    private suspend fun ensureEngine(voice: String): OfflineTts = engineLock.withLock {
        if (currentVoice == voice && tts != null) return@withLock tts!!
        tts?.release()
        tts = null

        val (modelFile, _) = ensureModelFiles(voice)
        val config = OfflineTtsConfig(
            model = OfflineTtsModelConfig(
                vits = OfflineTtsVitsModelConfig(
                    model = modelFile.absolutePath,
                    dataDir = modelFile.parentFile?.absolutePath.orEmpty(),
                    noiseScale = 0.667f,
                    noiseScaleW = 0.8f,
                    lengthScale = 1.0f,
                ),
                numThreads = 2,
                debug = false,
                provider = "cpu",
            ),
            maxNumSentences = 2,
        )
        tts = OfflineTts(config = config)
        currentVoice = voice
        tts!!
    }

    private suspend fun ensureModelFiles(voice: String): Pair<File, File> =
        withContext(Dispatchers.IO) {
            val voiceSpec = resolveVoiceSpec(voice)
            val modelFile = File(modelsDir, "$voice.onnx")
            val configFile = File(modelsDir, "$voice.onnx.json")
            ensureFile(voiceSpec.model, modelFile)
            ensureFile(voiceSpec.config, configFile)
            modelFile to configFile
        }

    private suspend fun resolveVoiceSpec(voice: String): VoiceSpec {
        val selectedVoice = if (VOICE_BASE_PATHS.containsKey(voice)) {
            voice
        } else {
            Log.w(TAG, "Unknown voice '$voice', falling back to $DEFAULT_VOICE")
            DEFAULT_VOICE
        }

        val manifest = getVoicesManifest()
        val voiceEntry = manifest.optJSONObject(selectedVoice)
            ?: error("Voice metadata missing for $selectedVoice")
        val files = voiceEntry.optJSONObject("files")
            ?: error("Voice file metadata missing for $selectedVoice")
        val basePath = VOICE_BASE_PATHS.getValue(selectedVoice)

        fun remoteFile(fileName: String): RemoteFile {
            val relativePath = "$basePath/$fileName"
            val fileEntry = files.optJSONObject(relativePath)
                ?: error("Voice asset missing from manifest: $relativePath")
            return RemoteFile(
                fileName = fileName,
                url = "$HF/$relativePath",
                md5 = fileEntry.getString("md5_digest"),
                sizeBytes = fileEntry.getLong("size_bytes")
            )
        }

        return VoiceSpec(
            model = remoteFile("$selectedVoice.onnx"),
            config = remoteFile("$selectedVoice.onnx.json")
        )
    }

    private suspend fun getVoicesManifest(): JSONObject = manifestLock.withLock {
        voicesManifest?.let { return@withLock it }

        val connection = (URL(VOICES_MANIFEST_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            requestMethod = "GET"
        }
        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                error("Failed to fetch Piper voices manifest ($status)")
            }
            val payload = connection.inputStream.bufferedReader().use { it.readText() }
            return@withLock JSONObject(payload).also { voicesManifest = it }
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun ensureFile(remoteFile: RemoteFile, dest: File) {
        if (dest.exists() && dest.length() > 0L && isValidFile(dest, remoteFile)) return

        dest.delete()
        dest.parentFile?.mkdirs()
        Log.i(TAG, "Downloading Piper asset: ${remoteFile.fileName}")
        val download = downloadWithManager(remoteFile)
        try {
            validateDownloadedFile(download.file, remoteFile)
            copyIntoPlace(download.file, dest)
        } finally {
            download.file.delete()
            downloadManager.remove(download.id)
        }
    }

    private suspend fun downloadWithManager(remoteFile: RemoteFile): DownloadedFile {
        val tempFile = File(stagingDir, "${remoteFile.fileName}.${System.nanoTime()}.download")
        tempFile.delete()

        val request = DownloadManager.Request(Uri.parse(remoteFile.url)).apply {
            setTitle("Downloading voice data")
            setDescription(remoteFile.fileName)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(false)
            setDestinationUri(Uri.fromFile(tempFile))
        }

        val downloadId = downloadManager.enqueue(request)
        while (true) {
            val query = DownloadManager.Query().setFilterById(downloadId)
            val cursor = downloadManager.query(query)
            cursor.use {
                if (!it.moveToFirst()) {
                    error("Download disappeared for ${remoteFile.fileName}")
                }
                when (it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                    DownloadManager.STATUS_SUCCESSFUL -> {
                        return DownloadedFile(id = downloadId, file = tempFile)
                    }
                    DownloadManager.STATUS_FAILED -> {
                        val reason = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                        error("Download failed for ${remoteFile.fileName} (reason=$reason)")
                    }
                    else -> Unit
                }
            }
            delay(DOWNLOAD_POLL_MS)
        }
    }

    private fun validateDownloadedFile(file: File, remoteFile: RemoteFile) {
        if (!file.exists() || file.length() <= 0L) {
            error("Downloaded Piper asset is empty: ${remoteFile.fileName}")
        }
        if (file.length() != remoteFile.sizeBytes) {
            error(
                "Downloaded Piper asset has wrong size for ${remoteFile.fileName} " +
                    "(${file.length()}/${remoteFile.sizeBytes})"
            )
        }
        val digest = md5(file)
        if (!digest.equals(remoteFile.md5, ignoreCase = true)) {
            error("Downloaded Piper asset failed MD5 check for ${remoteFile.fileName}")
        }
    }

    private fun isValidFile(file: File, remoteFile: RemoteFile): Boolean {
        return file.length() == remoteFile.sizeBytes &&
            md5(file).equals(remoteFile.md5, ignoreCase = true)
    }

    private fun copyIntoPlace(source: File, dest: File) {
        dest.parentFile?.mkdirs()
        source.inputStream().use { input ->
            FileOutputStream(dest).use { output ->
                input.copyTo(output)
            }
        }
    }

    private fun md5(file: File): String {
        val digest = MessageDigest.getInstance("MD5")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val bytesRead = input.read(buffer)
                if (bytesRead <= 0) break
                digest.update(buffer, 0, bytesRead)
            }
        }
        return digest.digest().joinToString(separator = "") { "%02x".format(it) }
    }

    private fun writePcmWav(file: File, samples: FloatArray, sampleRate: Int) {
        val dataSize = samples.size * 2
        val buf = ByteBuffer.allocate(44 + dataSize).order(ByteOrder.LITTLE_ENDIAN)
        buf.put("RIFF".toByteArray())
        buf.putInt(36 + dataSize)
        buf.put("WAVE".toByteArray())
        buf.put("fmt ".toByteArray())
        buf.putInt(16)
        buf.putShort(1)
        buf.putShort(1)
        buf.putInt(sampleRate)
        buf.putInt(sampleRate * 2)
        buf.putShort(2)
        buf.putShort(16)
        buf.put("data".toByteArray())
        buf.putInt(dataSize)
        for (sample in samples) {
            buf.putShort((sample.coerceIn(-1f, 1f) * 32767f).toInt().toShort())
        }
        FileOutputStream(file).use { it.write(buf.array()) }
    }

    override fun release() {
        tts?.release()
        tts = null
        currentVoice = null
    }

    companion object {
        private const val TAG = "PiperTtsClient"
        private const val DOWNLOAD_POLL_MS = 500L
        private const val HF = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0"
        private const val VOICES_MANIFEST_URL =
            "https://huggingface.co/rhasspy/piper-voices/raw/main/voices.json"

        const val DEFAULT_VOICE = "en_US-amy-medium"

        val VOICE_BASE_PATHS: Map<String, String> = mapOf(
            "en_US-amy-medium" to "en/en_US/amy/medium",
            "en_US-lessac-medium" to "en/en_US/lessac/medium",
            "en_US-ryan-medium" to "en/en_US/ryan/medium",
            "en_GB-alan-medium" to "en/en_GB/alan/medium"
        )

        val AVAILABLE_VOICES: List<String> = VOICE_BASE_PATHS.keys.toList()
    }

    private data class VoiceSpec(
        val model: RemoteFile,
        val config: RemoteFile
    )

    private data class RemoteFile(
        val fileName: String,
        val url: String,
        val md5: String,
        val sizeBytes: Long
    )

    private data class DownloadedFile(
        val id: Long,
        val file: File
    )
}
