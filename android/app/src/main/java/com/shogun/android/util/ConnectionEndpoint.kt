package com.shogun.android.util

import java.net.URI

data class ConnectionEndpoint(
    val host: String,
    val port: String?
)

fun normalizeConnectionEndpoint(raw: String): ConnectionEndpoint {
    val input = raw.trim()
    require(input.isNotBlank()) { "接続先を入力してください" }

    val parsed = runCatching {
        val uri = if (input.contains("://")) URI(input) else URI("ssh://$input")
        val host = uri.host?.trim()?.trim('[', ']')
        if (!host.isNullOrBlank()) {
            ConnectionEndpoint(
                host = host,
                port = uri.port.takeIf { it > 0 }?.toString()
            )
        } else {
            null
        }
    }.getOrNull()

    if (parsed != null) return parsed

    val withoutScheme = input.substringAfter("://", input)
    val authority = withoutScheme.substringBefore('/').substringBefore('?').substringBefore('#')
    val userless = authority.substringAfter('@')
    val host = userless.substringBefore(':').trim().trim('[', ']')
    val port = userless.substringAfter(':', "").trim().takeIf { it.all(Char::isDigit) && it.isNotBlank() }
    require(host.isNotBlank()) { "接続先を確認してください" }
    return ConnectionEndpoint(host = host, port = port)
}
