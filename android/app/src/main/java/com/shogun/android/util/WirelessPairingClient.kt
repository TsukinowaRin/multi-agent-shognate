package com.shogun.android.util

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

data class WirelessPairingResult(
    val host: String,
    val port: String,
    val user: String,
    val project: String,
    val shogunTarget: String,
    val agentsTarget: String,
    val keyPath: String,
    val runtimeStarted: Boolean,
    val runtimeMessage: String
)

object WirelessPairingClient {
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .readTimeout(180, TimeUnit.SECONDS)
        .build()

    suspend fun pair(
        context: Context,
        host: String,
        pairingPort: Int = Defaults.PAIRING_PORT
    ): Result<WirelessPairingResult> = withContext(Dispatchers.IO) {
        runCatching {
            val profile = AndroidSshKeyManager.ensurePairingProfile(context)
            val body = JSONObject()
                .put("public_key", profile.publicKey)
                .put("key_path", profile.keyPath)
                .put("device_label", profile.deviceLabel)
                .put("host", host)
                .toString()
                .toRequestBody(jsonMediaType)
            val request = Request.Builder()
                .url("http://${formatHost(host)}:$pairingPort/pair")
                .post(body)
                .build()

            client.newCall(request).execute().use { response ->
                val responseBody = response.body?.string().orEmpty()
                val json = responseBody.takeIf { it.isNotBlank() }?.let { JSONObject(it) } ?: JSONObject()
                if (!response.isSuccessful || !json.optBoolean("ok", false)) {
                    error(json.optString("error", "pairing failed: HTTP ${response.code}"))
                }
                WirelessPairingResult(
                    host = json.optString("host", host).ifBlank { host },
                    port = json.optString("port", Defaults.SSH_PORT_STR),
                    user = json.optString("user"),
                    project = json.optString("project"),
                    shogunTarget = json.optString("shogun", Defaults.SHOGUN_SESSION),
                    agentsTarget = json.optString("agents", Defaults.AGENTS_SESSION),
                    keyPath = json.optString("key_path", profile.keyPath).ifBlank { profile.keyPath },
                    runtimeStarted = json.optBoolean("runtime_started", false),
                    runtimeMessage = json.optString("runtime_message", "")
                )
            }
        }
    }

    private fun formatHost(host: String): String {
        val trimmed = host.trim().trim('[', ']')
        return if (trimmed.contains(":") && !trimmed.startsWith("[")) "[$trimmed]" else trimmed
    }
}
