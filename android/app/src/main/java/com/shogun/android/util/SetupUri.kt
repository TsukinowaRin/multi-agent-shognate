package com.shogun.android.util

import android.net.Uri

data class ShogunateSetupConfig(
    val host: String?,
    val port: String?,
    val user: String?,
    val keyPath: String?,
    val projectPath: String?,
    val shogunTarget: String?,
    val agentsTarget: String?
)

fun parseShogunateSetupUri(raw: String): ShogunateSetupConfig {
    val uri = Uri.parse(raw.trim())
    require(uri.scheme == "shogunate" && uri.host == "setup") {
        "shogunate://setup 形式ではありません"
    }

    val host = uri.getQueryParameter("host")?.trim()
    val port = uri.getQueryParameter("port")?.trim()
    require(!host.isNullOrBlank() && !port.isNullOrBlank()) {
        "host と port が必要です"
    }

    return ShogunateSetupConfig(
        host = host,
        port = port,
        user = uri.getQueryParameter("user")?.trim(),
        keyPath = uri.getQueryParameter("key")?.trim(),
        projectPath = uri.getQueryParameter("project")?.trim(),
        shogunTarget = uri.getQueryParameter("shogun")?.trim(),
        agentsTarget = uri.getQueryParameter("agents")?.trim()
    )
}
