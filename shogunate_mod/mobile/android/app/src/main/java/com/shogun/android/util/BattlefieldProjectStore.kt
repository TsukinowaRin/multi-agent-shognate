package com.shogun.android.util

import android.content.SharedPreferences
import org.json.JSONArray

class BattlefieldProjectStore(private val prefs: SharedPreferences) {

    fun projects(): List<BattlefieldProject> {
        val raw = prefs.getString(PrefsKeys.BATTLEFIELD_PROJECTS, "") ?: ""
        val parsed = runCatching {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val project = BattlefieldProject.fromJson(array.getJSONObject(index))
                    if (project.path.isNotBlank()) add(project)
                }
            }
        }.getOrDefault(emptyList())

        val legacyPath = prefs.getString(PrefsKeys.PROJECT_PATH, "") ?: ""
        val withLegacy = if (legacyPath.isBlank() || parsed.any { it.path == legacyPath.trim().trimEnd('/') }) {
            parsed
        } else {
            parsed + BattlefieldProject.create(legacyPath)
        }
        return withLegacy.sortedByDescending { it.lastOpenedAt }
    }

    fun remember(path: String, name: String = ""): BattlefieldProject {
        val project = BattlefieldProject.create(path, name)
        val current = projects().filterNot { it.path == project.path }
        save((listOf(project) + current).take(MAX_HISTORY))
        prefs.edit().putString(PrefsKeys.PROJECT_PATH, project.path).apply()
        return project
    }

    private fun save(projects: List<BattlefieldProject>) {
        val array = JSONArray()
        projects.forEach { array.put(it.toJson()) }
        prefs.edit().putString(PrefsKeys.BATTLEFIELD_PROJECTS, array.toString()).apply()
    }

    companion object {
        private const val MAX_HISTORY = 20
    }
}
