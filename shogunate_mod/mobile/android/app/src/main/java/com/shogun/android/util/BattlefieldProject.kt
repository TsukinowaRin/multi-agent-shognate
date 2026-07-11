package com.shogun.android.util

import org.json.JSONObject

data class BattlefieldProject(
    val path: String,
    val name: String,
    val lastOpenedAt: Long
) {
    val displayName: String
        get() = name.ifBlank {
            path.trimEnd('/').substringAfterLast('/').ifBlank { path }
        }

    fun toJson(): JSONObject = JSONObject()
        .put("path", path)
        .put("name", name)
        .put("lastOpenedAt", lastOpenedAt)

    companion object {
        fun create(path: String, name: String = "", lastOpenedAt: Long = System.currentTimeMillis()): BattlefieldProject =
            BattlefieldProject(
                path = path.trim().trimEnd('/'),
                name = name.trim(),
                lastOpenedAt = lastOpenedAt
            )

        fun fromJson(json: JSONObject): BattlefieldProject = BattlefieldProject(
            path = json.optString("path"),
            name = json.optString("name"),
            lastOpenedAt = json.optLong("lastOpenedAt", 0L)
        )
    }
}
