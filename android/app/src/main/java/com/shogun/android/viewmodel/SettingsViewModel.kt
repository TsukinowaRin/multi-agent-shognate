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

class SettingsViewModel(application: Application) : AndroidViewModel(application) {

    private val sshManager = SshManager.getInstance()
    private val prefs = application.getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)

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

    private val _updateLoading = MutableStateFlow(false)
    val updateLoading: StateFlow<Boolean> = _updateLoading

    private val _updateResult = MutableStateFlow("")
    val updateResult: StateFlow<String> = _updateResult

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

    fun checkHostUpdateStatus() {
        runRemoteUpdateCommand("python3 scripts/update_manager.py status")
    }

    fun previewUpstreamSync() {
        runRemoteUpdateCommand("python3 scripts/update_manager.py upstream-sync --dry-run")
    }

    fun stopAndApplyReleaseUpdate() {
        runRemoteUpdateCommand("bash scripts/stop_and_apply_update.sh manual --restart --requested-by android")
    }

    fun stopAndApplyUpstreamUpdate() {
        runRemoteUpdateCommand("bash scripts/stop_and_apply_update.sh upstream-sync --restart --requested-by android")
    }

    private fun runRemoteUpdateCommand(command: String) {
        viewModelScope.launch {
            _updateLoading.value = true
            val connect = ensureConnected()
            if (connect.isFailure) {
                _updateResult.value = "接続失敗: ${connect.exceptionOrNull()?.message}"
                _updateLoading.value = false
                return@launch
            }

            val projectPath = prefs.getString(PrefsKeys.PROJECT_PATH, Defaults.PROJECT_PATH)?.trim().orEmpty()
            if (projectPath.isBlank()) {
                _updateResult.value = "設定画面でプロジェクトパスを保存してください"
                _updateLoading.value = false
                return@launch
            }

            val wrapped = "cd ${shellQuote(projectPath)} && $command"
            val result = sshManager.execCommand(wrapped)
            _updateResult.value = if (result.isSuccess) {
                result.getOrDefault("").ifBlank { "[ok] 出力なし" }
            } else {
                "実行失敗: ${result.exceptionOrNull()?.message}"
            }
            _updateLoading.value = false
        }
    }

    private suspend fun ensureConnected(): Result<Unit> {
        if (sshManager.isConnected()) return Result.success(Unit)

        val host = prefs.getString(PrefsKeys.SSH_HOST, Defaults.SSH_HOST)?.trim().orEmpty()
        val portText = prefs.getString(PrefsKeys.SSH_PORT, Defaults.SSH_PORT_STR)?.trim().orEmpty()
        val user = prefs.getString(PrefsKeys.SSH_USER, "")?.trim().orEmpty()
        val keyPath = prefs.getString(PrefsKeys.SSH_KEY_PATH, "")?.trim().orEmpty()
        val password = prefs.getString(PrefsKeys.SSH_PASSWORD, "") ?: ""

        if (host.isBlank() || user.isBlank() || portText.isBlank()) {
            return Result.failure(IllegalStateException("SSH設定を保存してから実行してください"))
        }

        val port = portText.toIntOrNull()
            ?: return Result.failure(IllegalStateException("SSHポートが不正です"))

        return sshManager.connect(host, port, user, keyPath, password)
    }

    private fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"
}
