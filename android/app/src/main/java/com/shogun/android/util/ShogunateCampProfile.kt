package com.shogun.android.util

import org.json.JSONObject
import java.security.MessageDigest

data class ShogunateCampProfile(
    val id: String,
    val name: String,
    val host: String,
    val port: String,
    val user: String,
    val keyPath: String,
    val password: String,
    val projectPath: String,
    val shogunTarget: String,
    val agentsTarget: String
) {
    val displayName: String
        get() = name.ifBlank {
            val project = projectPath.trimEnd('/').substringAfterLast('/').ifBlank { "Shogunate" }
            "$project @$host:$port"
        }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("host", host)
        .put("port", port)
        .put("user", user)
        .put("keyPath", keyPath)
        .put("password", password)
        .put("projectPath", projectPath)
        .put("shogunTarget", shogunTarget)
        .put("agentsTarget", agentsTarget)

    companion object {
        fun stableId(host: String, port: String, user: String, projectPath: String): String {
            val source = listOf(host.trim(), port.trim(), user.trim(), projectPath.trim()).joinToString("|")
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(source.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }
                .take(12)
            return "camp_$digest"
        }

        fun fromJson(json: JSONObject): ShogunateCampProfile = ShogunateCampProfile(
            id = json.optString("id"),
            name = json.optString("name"),
            host = json.optString("host", Defaults.SSH_HOST),
            port = json.optString("port", Defaults.SSH_PORT_STR),
            user = json.optString("user"),
            keyPath = json.optString("keyPath"),
            password = json.optString("password"),
            projectPath = json.optString("projectPath"),
            shogunTarget = json.optString("shogunTarget", Defaults.SHOGUN_SESSION),
            agentsTarget = json.optString("agentsTarget", Defaults.AGENTS_SESSION)
        )

        fun create(
            name: String,
            host: String,
            port: String,
            user: String,
            keyPath: String,
            password: String,
            projectPath: String,
            shogunTarget: String,
            agentsTarget: String,
            id: String = stableId(host, port, user, projectPath)
        ): ShogunateCampProfile = ShogunateCampProfile(
            id = id,
            name = name.trim(),
            host = host.trim(),
            port = port.trim(),
            user = user.trim(),
            keyPath = keyPath.trim(),
            password = password,
            projectPath = projectPath.trim(),
            shogunTarget = shogunTarget.trim().ifBlank { Defaults.SHOGUN_SESSION },
            agentsTarget = agentsTarget.trim().ifBlank { Defaults.AGENTS_SESSION }
        )
    }
}
