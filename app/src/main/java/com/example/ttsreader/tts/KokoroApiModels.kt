package com.example.ttsreader.tts

data class KokoroRequest(
    val text: String,
    val voice: String = "af_bella",
    val model: String = "kokoro",
    val format: String = "mp3"
)

data class KokoroQueuedResponse(
    val uuid: String? = null,
    val job_id: String? = null,
    val status: String? = null
)

data class KokoroResultResponse(
    val status: String,
    val result_url: String? = null,
    val error: String? = null
)