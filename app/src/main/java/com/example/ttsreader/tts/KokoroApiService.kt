package com.example.ttsreader.tts

import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Headers
import retrofit2.http.POST
import retrofit2.http.Query
import retrofit2.http.Streaming

interface KokoroApiService {
    @Streaming
    @Headers("Content-Type: application/json")
    @POST("v1/tts/")
    suspend fun synthesize(@Body request: KokoroRequest): Response<ResponseBody>

    @GET("v1/speech/results/")
    suspend fun pollResult(@Query("uuid") uuid: String): Response<KokoroResultResponse>
}