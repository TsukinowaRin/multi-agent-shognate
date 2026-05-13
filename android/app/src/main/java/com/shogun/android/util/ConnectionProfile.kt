package com.shogun.android.util

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

    private fun stringValue(source: String, key: String): String? {
        val match = Regex(""""${Regex.escape(key)}"\s*:\s*"((?:\\.|[^"\\])*)"""").find(source)
        return match?.groupValues?.get(1)?.replace("\\\"", "\"")?.replace("\\n", "\n")?.replace("\\\\", "\\")
    }

    private fun numberValue(source: String, key: String): String? {
        return Regex(""""${Regex.escape(key)}"\s*:\s*(\d+)""").find(source)?.groupValues?.get(1)
    }
}
