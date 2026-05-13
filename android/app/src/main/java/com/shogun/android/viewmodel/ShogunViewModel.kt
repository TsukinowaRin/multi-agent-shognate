package com.shogun.android.viewmodel

import android.app.Application
import android.content.Context
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.shogun.android.SshForegroundService
import com.shogun.android.ssh.SshManager
import com.shogun.android.util.AgentTarget
import com.shogun.android.util.AgentTargets
import com.shogun.android.util.Defaults
import com.shogun.android.util.PrefsKeys
import java.util.Base64
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class ShogunViewModel(application: Application) : AndroidViewModel(application) {

    private val sshManager = SshManager.getInstance()
    private val prefs = application.getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)

    private val _paneContent = MutableStateFlow("")
    val paneContent: StateFlow<String> = _paneContent

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage

    private val _agentTargets = MutableStateFlow(listOf(AgentTargets.default))
    val agentTargets: StateFlow<List<AgentTarget>> = _agentTargets

    private val _selectedAgentId = MutableStateFlow(AgentTargets.default.id)
    val selectedAgentId: StateFlow<String> = _selectedAgentId

    private var refreshJob: Job? = null
    private var reconnectJob: Job? = null
    @Volatile private var paused = false

    private fun tmuxTarget(): String {
        val session = prefs.getString(PrefsKeys.SHOGUN_SESSION, Defaults.SHOGUN_SESSION) ?: Defaults.SHOGUN_SESSION
        return "$session:main"
    }

    private fun projectPath(): String =
        prefs.getString(PrefsKeys.PROJECT_PATH, Defaults.PROJECT_PATH)?.trim().orEmpty()

    private fun bridgeCommand(args: String): String? {
        val path = projectPath()
        if (path.isBlank()) return null
        return "cd ${shellQuote(path)} && bash scripts/android_agent_bridge.sh $args"
    }

    fun pauseRefresh() { paused = true }
    fun resumeRefresh() {
        paused = false
        viewModelScope.launch {
            if (sshManager.isConnected()) refreshAgentTargets()
            refreshSelectedAgent()
        }
    }

    fun connect(host: String, port: Int, user: String, keyPath: String, password: String = "") {
        viewModelScope.launch {
            val result = sshManager.connect(
                host, port, user, keyPath, password,
                onDisconnect = {
                    _isConnected.value = false
                    startReconnect()
                }
            )
            if (result.isSuccess) {
                _isConnected.value = true
                _errorMessage.value = null
                startForegroundService()
                refreshAgentTargets()
                startAutoRefresh()
            } else {
                _errorMessage.value = "接続失敗: ${result.exceptionOrNull()?.message}"
            }
        }
    }

    fun selectAgentTarget(agentId: String) {
        _selectedAgentId.value = agentId
        viewModelScope.launch { refreshSelectedAgent() }
    }

    private fun startAutoRefresh() {
        refreshJob?.cancel()
        refreshJob = viewModelScope.launch {
            while (isActive) {
                if (!paused && sshManager.isConnected()) {
                    refreshAgentTargets()
                    refreshSelectedAgent()
                }
                delay(3000)
            }
        }
    }

    private suspend fun refreshAgentTargets() {
        val cmd = bridgeCommand("list") ?: return
        val result = sshManager.execCommand(cmd)
        if (result.isSuccess) {
            val targets = AgentTargets.parseBridgeList(result.getOrDefault(""))
            _agentTargets.value = targets
            if (targets.none { it.id == _selectedAgentId.value }) {
                _selectedAgentId.value = AgentTargets.default.id
            }
        }
    }

    private suspend fun refreshSelectedAgent() {
        if (!sshManager.isConnected()) return
        val agentId = _selectedAgentId.value
        val bridge = bridgeCommand("capture ${shellQuote(agentId)}")
        val result = if (bridge != null) sshManager.execCommand(bridge) else Result.failure(IllegalStateException("bridge unavailable"))
        if (result.isSuccess) {
            _paneContent.value = result.getOrDefault("")
            _errorMessage.value = null
            return
        }

        if (agentId == AgentTargets.default.id) {
            val fallback = sshManager.execCommand("${Defaults.TMUX} capture-pane -t ${tmuxTarget()} -p -e -S -500")
            if (fallback.isSuccess) {
                _paneContent.value = fallback.getOrDefault("")
                _errorMessage.value = null
            } else {
                _errorMessage.value = fallback.exceptionOrNull()?.message
            }
        } else {
            _errorMessage.value = "agent capture failed: ${result.exceptionOrNull()?.message}"
        }
    }

    fun sendCommand(text: String) {
        viewModelScope.launch {
            val agentId = _selectedAgentId.value
            val encoded = Base64.getEncoder().encodeToString(text.toByteArray(Charsets.UTF_8))
            val bridge = bridgeCommand("send-b64 ${shellQuote(agentId)} ${shellQuote(encoded)}")
            val sendResult = if (bridge != null) sshManager.execCommand(bridge) else Result.failure(IllegalStateException("bridge unavailable"))
            if (sendResult.isFailure && agentId == AgentTargets.default.id) {
                val target = tmuxTarget()
                val escaped = text.replace("'", "'\\''")
                // Send text and Enter SEPARATELY with 0.3s gap (Claude Code requirement)
                sshManager.execCommand("${Defaults.TMUX} send-keys -t $target '$escaped'")
                delay(300)
                sshManager.execCommand("${Defaults.TMUX} send-keys -t $target Enter")
            } else if (sendResult.isFailure) {
                _errorMessage.value = "agent send failed: ${sendResult.exceptionOrNull()?.message}"
                return@launch
            }
            delay(1500)
            refreshSelectedAgent()
        }
    }

    private fun startReconnect() {
        reconnectJob?.cancel()
        reconnectJob = viewModelScope.launch {
            _paneContent.value += "\n[自動再接続中...]\n"
            val result = sshManager.reconnect(maxAttempts = 3, delayMs = 5000)
            if (result.isSuccess) {
                _isConnected.value = true
                _errorMessage.value = null
                _paneContent.value += "[再接続成功]\n"
                startForegroundService()
                startAutoRefresh()
            } else {
                _isConnected.value = false
                _errorMessage.value = "再接続失敗: ${result.exceptionOrNull()?.message}"
                _paneContent.value += "[再接続失敗。手動で再接続してください]\n"
                stopForegroundService()
            }
        }
    }

    private fun startForegroundService() {
        try {
            val ctx = getApplication<Application>()
            val intent = Intent(ctx, SshForegroundService::class.java)
            ctx.startForegroundService(intent)
        } catch (_: Exception) {
            // Foreground service start blocked by system — SSH works without it
        }
    }

    private fun stopForegroundService() {
        val ctx = getApplication<Application>()
        val intent = Intent(ctx, SshForegroundService::class.java)
        ctx.stopService(intent)
    }

    private fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"

    override fun onCleared() {
        super.onCleared()
        refreshJob?.cancel()
        reconnectJob?.cancel()
    }
}
