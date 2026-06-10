package com.shogun.android.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.shogun.android.ssh.SshManager
import com.shogun.android.util.Defaults
import com.shogun.android.util.PrefsKeys
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

data class ConnectionTestState(
    val running: Boolean = false,
    val success: Boolean = false,
    val message: String = ""
)

class SettingsViewModel(application: Application) : AndroidViewModel(application) {

    private val prefs = application.getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)
    private val sshManager = SshManager.getInstance()

    private val _notificationEnabled = MutableStateFlow(prefs.getBoolean(PrefsKeys.NOTIFICATION_ENABLED, true))
    val notificationEnabled: StateFlow<Boolean> = _notificationEnabled

    private val _ntfyTopic = MutableStateFlow(prefs.getString(PrefsKeys.NTFY_TOPIC, Defaults.NTFY_TOPIC) ?: Defaults.NTFY_TOPIC)
    val ntfyTopic: StateFlow<String> = _ntfyTopic

    private val _notifyCmdComplete = MutableStateFlow(prefs.getBoolean(PrefsKeys.NOTIFY_CMD_COMPLETE, true))
    val notifyCmdComplete: StateFlow<Boolean> = _notifyCmdComplete

    private val _notifyCmdFailure = MutableStateFlow(prefs.getBoolean(PrefsKeys.NOTIFY_CMD_FAILURE, true))
    val notifyCmdFailure: StateFlow<Boolean> = _notifyCmdFailure

    private val _notifyActionRequired = MutableStateFlow(prefs.getBoolean(PrefsKeys.NOTIFY_ACTION_REQUIRED, true))
    val notifyActionRequired: StateFlow<Boolean> = _notifyActionRequired

    private val _notifyDashboardUpdate = MutableStateFlow(prefs.getBoolean(PrefsKeys.NOTIFY_DASHBOARD_UPDATE, false))
    val notifyDashboardUpdate: StateFlow<Boolean> = _notifyDashboardUpdate

    private val _notifyStreakUpdate = MutableStateFlow(prefs.getBoolean(PrefsKeys.NOTIFY_STREAK_UPDATE, false))
    val notifyStreakUpdate: StateFlow<Boolean> = _notifyStreakUpdate

    private val _notifyAgentResponse = MutableStateFlow(prefs.getBoolean(PrefsKeys.NOTIFY_AGENT_RESPONSE, false))
    val notifyAgentResponse: StateFlow<Boolean> = _notifyAgentResponse

    private val _connectionTest = MutableStateFlow(ConnectionTestState())
    val connectionTest: StateFlow<ConnectionTestState> = _connectionTest

    fun setNotificationEnabled(value: Boolean) {
        _notificationEnabled.value = value
        prefs.edit().putBoolean(PrefsKeys.NOTIFICATION_ENABLED, value).apply()
    }

    fun setNtfyTopic(value: String) {
        _ntfyTopic.value = value
        prefs.edit().putString(PrefsKeys.NTFY_TOPIC, value).apply()
    }

    fun setNotifyCmdComplete(value: Boolean) {
        _notifyCmdComplete.value = value
        prefs.edit().putBoolean(PrefsKeys.NOTIFY_CMD_COMPLETE, value).apply()
    }

    fun setNotifyCmdFailure(value: Boolean) {
        _notifyCmdFailure.value = value
        prefs.edit().putBoolean(PrefsKeys.NOTIFY_CMD_FAILURE, value).apply()
    }

    fun setNotifyActionRequired(value: Boolean) {
        _notifyActionRequired.value = value
        prefs.edit().putBoolean(PrefsKeys.NOTIFY_ACTION_REQUIRED, value).apply()
    }

    fun setNotifyDashboardUpdate(value: Boolean) {
        _notifyDashboardUpdate.value = value
        prefs.edit().putBoolean(PrefsKeys.NOTIFY_DASHBOARD_UPDATE, value).apply()
    }

    fun setNotifyStreakUpdate(value: Boolean) {
        _notifyStreakUpdate.value = value
        prefs.edit().putBoolean(PrefsKeys.NOTIFY_STREAK_UPDATE, value).apply()
    }

    fun setNotifyAgentResponse(value: Boolean) {
        _notifyAgentResponse.value = value
        prefs.edit().putBoolean(PrefsKeys.NOTIFY_AGENT_RESPONSE, value).apply()
    }

    fun testConnection(
        host: String,
        portText: String,
        user: String,
        keyPath: String,
        password: String,
        projectPath: String,
        shogunTargetInput: String,
        agentsTargetInput: String
    ) {
        val trimmedHost = host.trim()
        val trimmedUser = user.trim()
        val port = portText.trim().toIntOrNull()
        if (trimmedHost.isBlank() || trimmedUser.isBlank() || port == null) {
            _connectionTest.value = ConnectionTestState(
                running = false,
                success = false,
                message = "SSHホスト、ポート、ユーザーを確認してください。"
            )
            return
        }

        viewModelScope.launch {
            _connectionTest.value = ConnectionTestState(running = true, message = "SSH接続中...")
            val lines = mutableListOf<String>()
            val sshResult = sshManager.connect(trimmedHost, port, trimmedUser, keyPath.trim(), password)
            if (sshResult.isFailure) {
                _connectionTest.value = ConnectionTestState(
                    running = false,
                    success = false,
                    message = "SSH: 失敗\n${sshResult.exceptionOrNull()?.message ?: "不明なエラー"}"
                )
                return@launch
            }
            lines += "接続: OK"

            val tmuxOk = remoteOk("command -v tmux >/dev/null 2>&1")
            lines += "tmux: " + if (tmuxOk) "OK" else "見つかりません"

            val trimmedProject = projectPath.trim().trimEnd('/')
            val projectOk = trimmedProject.isNotBlank() && remoteOk("[ -d ${shellQuote(trimmedProject)} ]")
            lines += "Project: " + when {
                trimmedProject.isBlank() -> "未設定"
                projectOk -> "OK ($trimmedProject)"
                else -> "見つかりません ($trimmedProject)"
            }

            val shogunTarget = Defaults.resolveShogunTarget(shogunTargetInput)
            val agentsTarget = Defaults.resolveAgentsTarget(agentsTargetInput)
            val shogunOk = remoteOk(Defaults.shogunTargetExistsCommand(shogunTargetInput))
            val agentsOk = remoteOk(Defaults.agentsTargetExistsCommand(agentsTargetInput))
            lines += "将軍 target: " + if (shogunOk) "OK ($shogunTarget)" else "見つかりません ($shogunTarget)"
            lines += "エージェント target: " + if (agentsOk) "OK ($agentsTarget)" else "見つかりません ($agentsTarget)"

            if (trimmedProject.isNotBlank()) {
                val dashboardOk = remoteOk("[ -f ${shellQuote("$trimmedProject/dashboard.md")} ]")
                lines += "dashboard.md: " + if (dashboardOk) "OK" else "未検出"
            }

            val success = tmuxOk && shogunOk && agentsOk && (trimmedProject.isBlank() || projectOk)
            _connectionTest.value = ConnectionTestState(
                running = false,
                success = success,
                message = lines.joinToString("\n")
            )
        }
    }

    private suspend fun remoteOk(testCommand: String): Boolean {
        val result = sshManager.execCommand("if $testCommand; then echo __ok__; else echo __ng__; fi")
        return result.getOrDefault("").contains("__ok__")
    }

    private fun shellQuote(value: String): String = Defaults.shellQuote(value)
}
