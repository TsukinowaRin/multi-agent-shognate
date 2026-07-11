package com.shogun.android.util

import android.content.SharedPreferences
import org.json.JSONArray

class ShogunateCampProfileStore(private val prefs: SharedPreferences) {

    fun profiles(): List<ShogunateCampProfile> {
        val raw = prefs.getString(PrefsKeys.CAMP_PROFILES, "") ?: ""
        val parsed = runCatching {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val profile = ShogunateCampProfile.fromJson(array.getJSONObject(index))
                    if (profile.id.isNotBlank()) add(profile)
                }
            }
        }.getOrDefault(emptyList())

        if (parsed.isNotEmpty()) return parsed

        val legacy = legacyProfile() ?: return emptyList()
        saveProfiles(listOf(legacy))
        prefs.edit().putString(PrefsKeys.ACTIVE_CAMP_ID, legacy.id).apply()
        return listOf(legacy)
    }

    fun activeProfile(): ShogunateCampProfile? {
        val all = profiles()
        val activeId = prefs.getString(PrefsKeys.ACTIVE_CAMP_ID, "") ?: ""
        return all.firstOrNull { it.id == activeId } ?: all.firstOrNull()
    }

    fun upsert(profile: ShogunateCampProfile) {
        val current = profiles().filterNot { it.id == profile.id }
        saveProfiles(current + profile)
        select(profile.id)
    }

    fun select(id: String): ShogunateCampProfile? {
        val profile = profiles().firstOrNull { it.id == id } ?: return null
        prefs.edit().putString(PrefsKeys.ACTIVE_CAMP_ID, profile.id).apply()
        applyLegacy(profile)
        return profile
    }

    fun profileFromFields(
        name: String,
        host: String,
        port: String,
        user: String,
        keyPath: String,
        password: String,
        projectPath: String,
        shogunTarget: String,
        agentsTarget: String
    ): ShogunateCampProfile {
        val trimmedHost = host.trim()
        val trimmedPort = port.trim()
        val trimmedUser = user.trim()
        val trimmedProjectPath = projectPath.trim()
        val active = activeProfile()
        val id = if (
            active != null &&
            active.host == trimmedHost &&
            active.port == trimmedPort &&
            active.user == trimmedUser &&
            active.projectPath == trimmedProjectPath
        ) {
            active.id
        } else {
            ShogunateCampProfile.stableId(trimmedHost, trimmedPort, trimmedUser, trimmedProjectPath)
        }
        val existingName = profiles().firstOrNull { it.id == id }?.name.orEmpty()
        return ShogunateCampProfile.create(
            id = id,
            name = name.ifBlank { existingName },
            host = trimmedHost,
            port = trimmedPort,
            user = trimmedUser,
            keyPath = keyPath,
            password = password,
            projectPath = trimmedProjectPath,
            shogunTarget = shogunTarget,
            agentsTarget = agentsTarget
        )
    }

    private fun saveProfiles(profiles: List<ShogunateCampProfile>) {
        val array = JSONArray()
        profiles.forEach { array.put(it.toJson()) }
        prefs.edit().putString(PrefsKeys.CAMP_PROFILES, array.toString()).apply()
    }

    private fun legacyProfile(): ShogunateCampProfile? {
        val host = prefs.getString(PrefsKeys.SSH_HOST, Defaults.SSH_HOST) ?: Defaults.SSH_HOST
        val port = prefs.getString(PrefsKeys.SSH_PORT, Defaults.SSH_PORT_STR) ?: Defaults.SSH_PORT_STR
        val user = prefs.getString(PrefsKeys.SSH_USER, "") ?: ""
        val keyPath = prefs.getString(PrefsKeys.SSH_KEY_PATH, "") ?: ""
        val password = prefs.getString(PrefsKeys.SSH_PASSWORD, "") ?: ""
        val projectPath = prefs.getString(PrefsKeys.PROJECT_PATH, "") ?: ""
        val shogunTarget = prefs.getString(PrefsKeys.SHOGUN_SESSION, Defaults.SHOGUN_SESSION) ?: Defaults.SHOGUN_SESSION
        val agentsTarget = prefs.getString(PrefsKeys.AGENTS_SESSION, Defaults.AGENTS_SESSION) ?: Defaults.AGENTS_SESSION
        if (user.isBlank() && keyPath.isBlank() && projectPath.isBlank()) return null
        return ShogunateCampProfile.create(
            name = "",
            host = host,
            port = port,
            user = user,
            keyPath = keyPath,
            password = password,
            projectPath = projectPath,
            shogunTarget = shogunTarget,
            agentsTarget = agentsTarget
        )
    }

    private fun applyLegacy(profile: ShogunateCampProfile) {
        prefs.edit()
            .putString(PrefsKeys.SSH_HOST, profile.host)
            .putString(PrefsKeys.SSH_PORT, profile.port)
            .putString(PrefsKeys.SSH_USER, profile.user)
            .putString(PrefsKeys.SSH_KEY_PATH, profile.keyPath)
            .putString(PrefsKeys.SSH_PASSWORD, profile.password)
            .putString(PrefsKeys.PROJECT_PATH, profile.projectPath)
            .putString(PrefsKeys.SHOGUN_SESSION, profile.shogunTarget)
            .putString(PrefsKeys.AGENTS_SESSION, profile.agentsTarget)
            .apply()
    }
}
