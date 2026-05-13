package com.shogun.android.util

import java.net.URLDecoder

data class ConnectionProfile(
    val host: String,
    val port: String,
    val user: String,
    val projectPath: String = "",
    val shogunSession: String = "shogun",
    val agentsSession: String = "multiagent"
)

object ConnectionProfiles {
    fun parse(text: String): ConnectionProfile? {
        val trimmed = text.trim()
        if (trimmed.startsWith("shogunate://")) return parseDeepLink(trimmed)
        val body = text.substringAfter('{', "").substringBeforeLast('}', "")
        if (body.isBlank()) return null
        val source = "{$body}"
        val host = stringValue(source, "host").orEmpty()
        val port = stringValue(source, "port") ?: numberValue(source, "port").orEmpty()
        val user = stringValue(source, "user").orEmpty()
        if (host.isBlank() || port.isBlank() || user.isBlank()) return null
        return ConnectionProfile(
            host = host,
            port = port,
            user = user,
            projectPath = stringValue(source, "projectPath").orEmpty(),
            shogunSession = stringValue(source, "shogunSession").orEmpty().ifBlank { "shogun" },
            agentsSession = stringValue(source, "agentsSession").orEmpty().ifBlank { "multiagent" }
        )
    }

    fun toPrefsMap(profile: ConnectionProfile): Map<String, String> = buildMap {
        put(PrefsKeys.SSH_HOST, profile.host)
        put(PrefsKeys.SSH_PORT, profile.port)
        put(PrefsKeys.SSH_USER, profile.user)
        if (profile.projectPath.isNotBlank()) put(PrefsKeys.PROJECT_PATH, profile.projectPath)
        put(PrefsKeys.SHOGUN_SESSION, profile.shogunSession)
        put(PrefsKeys.AGENTS_SESSION, profile.agentsSession)
    }

    private fun parseDeepLink(text: String): ConnectionProfile? {
        val query = text.substringAfter('?', "")
        if (query.isBlank()) return null
        val params = query.split('&')
            .mapNotNull { part ->
                val key = part.substringBefore('=', "")
                if (key.isBlank()) return@mapNotNull null
                val value = part.substringAfter('=', "")
                key to urlDecode(value)
            }
            .toMap()
        val host = params["host"].orEmpty()
        val port = params["port"].orEmpty()
        val user = params["user"].orEmpty()
        if (host.isBlank() || port.isBlank() || user.isBlank()) return null
        return ConnectionProfile(
            host = host,
            port = port,
            user = user,
            projectPath = params["projectPath"].orEmpty(),
            shogunSession = params["shogunSession"].orEmpty().ifBlank { "shogun" },
            agentsSession = params["agentsSession"].orEmpty().ifBlank { "multiagent" }
        )
    }

    private fun stringValue(source: String, key: String): String? {
        val match = Regex(""""${Regex.escape(key)}"\s*:\s*"((?:\\.|[^"\\])*)"""").find(source)
        return match?.groupValues?.get(1)?.replace("\\\"", "\"")?.replace("\\n", "\n")?.replace("\\\\", "\\")
    }

    private fun numberValue(source: String, key: String): String? {
        return Regex(""""${Regex.escape(key)}"\s*:\s*(\d+)""").find(source)?.groupValues?.get(1)
    }

    private fun urlDecode(value: String): String =
        URLDecoder.decode(value.replace("+", "%2B"), "UTF-8")
}
