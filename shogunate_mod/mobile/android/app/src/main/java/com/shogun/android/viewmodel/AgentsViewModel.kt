package com.shogun.android.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.shogun.android.ssh.SshManager
import com.shogun.android.util.Defaults
import com.shogun.android.util.PrefsKeys
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class PaneInfo(
    val index: Int,
    val agentId: String,
    val modelName: String,
    val content: String
)

class AgentsViewModel(application: Application) : AndroidViewModel(application) {

    private val sshManager = SshManager.getInstance()
    private val prefs = application.getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)

    private val _panes = MutableStateFlow<List<PaneInfo>>(emptyList())
    val panes: StateFlow<List<PaneInfo>> = _panes

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage

    private val _rateLimitResult = MutableStateFlow<String?>(null)
    val rateLimitResult: StateFlow<String?> = _rateLimitResult

    private val _rateLimitLoading = MutableStateFlow(false)
    val rateLimitLoading: StateFlow<Boolean> = _rateLimitLoading

    private var refreshJob: Job? = null
    private var reconnectJob: Job? = null
    @Volatile private var paused = false
    @Volatile private var isRefreshing = false

    private fun agentsTarget(): String {
        val session = prefs.getString(PrefsKeys.AGENTS_SESSION, Defaults.AGENTS_SESSION) ?: Defaults.AGENTS_SESSION
        return Defaults.resolveAgentsTarget(session)
    }

    fun pauseRefresh() { paused = true }
    fun resumeRefresh() {
        paused = false
        viewModelScope.launch {
            if (!sshManager.isConnected()) {
                connectFromPrefs()
                return@launch
            }
            refreshAllPanesInternal()
        }
    }

    private fun connectFromPrefs() {
        val host = prefs.getString(PrefsKeys.SSH_HOST, Defaults.SSH_HOST) ?: Defaults.SSH_HOST
        val port = prefs.getString(PrefsKeys.SSH_PORT, Defaults.SSH_PORT_STR)?.toIntOrNull() ?: Defaults.SSH_PORT
        val user = prefs.getString(PrefsKeys.SSH_USER, "") ?: ""
        val keyPath = prefs.getString(PrefsKeys.SSH_KEY_PATH, "") ?: ""
        val password = prefs.getString(PrefsKeys.SSH_PASSWORD, "") ?: ""
        connect(host, port, user, keyPath, password)
    }

    fun connect(host: String, port: Int, user: String, keyPath: String, password: String = "") {
        viewModelScope.launch {
            val result = sshManager.connect(host, port, user, keyPath, password)
            if (result.isSuccess) {
                _isConnected.value = true
                _errorMessage.value = null
                startAutoRefresh()
            } else {
                _errorMessage.value = "接続失敗: ${result.exceptionOrNull()?.message}"
                startReconnect()
            }
        }
    }

    private fun startReconnect() {
        reconnectJob?.cancel()
        reconnectJob = viewModelScope.launch {
            delay(3000)
            val result = sshManager.reconnect(maxAttempts = 3, delayMs = 5000)
            if (result.isSuccess) {
                _isConnected.value = true
                _errorMessage.value = null
                startAutoRefresh()
                refreshAllPanesInternal()
            } else {
                _isConnected.value = false
                _errorMessage.value = "再接続失敗: ${result.exceptionOrNull()?.message}"
            }
        }
    }

    private fun startAutoRefresh() {
        refreshJob?.cancel()
        refreshJob = viewModelScope.launch {
            while (isActive) {
                if (!paused && !isRefreshing) {
                    refreshAllPanesInternal()
                }
                delay(5000)
            }
        }
    }

    fun refreshAllPanes() {
        viewModelScope.launch { refreshAllPanesInternal() }
    }

    private suspend fun refreshAllPanesInternal() {
        if (isRefreshing) return
        isRefreshing = true
        try {
            val target = agentsTarget()
            val tmux = Defaults.TMUX
            // Single SSH call: detect pane count + batch-fetch all panes
            val batchCmd = buildString {
                append("if ! $tmux list-panes -t $target >/dev/null 2>&1; then echo \"===ERROR=target_not_found===\"; exit 0; fi; ")
                append("N=\$($tmux list-panes -t $target 2>/dev/null | wc -l); ")
                append("echo \"===PANE_COUNT=\$N===\"; ")
                append("for i in \$(seq 0 \$((N-1))); do ")
                append("echo \"===ID\$i===\"; ")
                append("$tmux display-message -t $target.\$i -p '#{@agent_id}' 2>/dev/null || echo \"pane\$i\"; ")
                append("echo \"===MODEL\$i===\"; ")
                append("$tmux show-options -p -t $target.\$i -v @model_name 2>/dev/null || echo ''; ")
                append("echo \"===CONTENT\$i===\"; ")
                append("$tmux capture-pane -e -t $target.\$i -p -S -50 2>/dev/null; ")
                append("done")
            }
            val result = sshManager.execCommand(batchCmd)
            if (result.isSuccess) {
                val output = result.getOrDefault("")
                if (output.contains("===ERROR=target_not_found===")) {
                    _panes.value = emptyList()
                    _errorMessage.value = "エージェント view が見つかりません。設定のエージェント target と Shogunate runtime を確認してください。"
                } else {
                    val newPanes = parseBatchOutput(output)
                    _panes.value = newPanes
                    _errorMessage.value = if (newPanes.isEmpty()) {
                        "エージェント pane がありません。Shogunate runtime を起動してから再読込してください。"
                    } else {
                        null
                    }
                }
            } else {
                _errorMessage.value = "エージェント一覧の取得に失敗しました: ${result.exceptionOrNull()?.message ?: "不明なエラー"}"
                _isConnected.value = false
                connectFromPrefs()
            }
        } finally {
            isRefreshing = false
        }
    }

    private fun parseBatchOutput(output: String): List<PaneInfo> {
        val countMatch = Regex("===PANE_COUNT=(\\d+)===").find(output)
        val paneCount = countMatch?.groupValues?.get(1)?.toIntOrNull() ?: return emptyList()
        val panes = mutableListOf<PaneInfo>()
        for (i in 0 until paneCount) {
            val idMarker = "===ID$i==="
            val modelMarker = "===MODEL$i==="
            val contentMarker = "===CONTENT$i==="
            val nextIdMarker = "===ID${i + 1}==="

            val idStart = output.indexOf(idMarker)
            val modelStart = output.indexOf(modelMarker)
            val contentStart = output.indexOf(contentMarker)
            if (idStart == -1 || contentStart == -1) {
                panes.add(PaneInfo(index = i, agentId = "pane$i", modelName = "", content = ""))
                continue
            }

            val agentId = output.substring(idStart + idMarker.length, modelStart.takeIf { it != -1 } ?: contentStart).trim()
            val modelName = if (modelStart != -1) {
                output.substring(modelStart + modelMarker.length, contentStart).trim()
            } else ""
            val contentEnd = if (i < paneCount - 1) {
                val next = output.indexOf(nextIdMarker)
                if (next != -1) next else output.length
            } else {
                output.length
            }
            val content = output.substring(contentStart + contentMarker.length, contentEnd).trim()
            panes.add(PaneInfo(index = i, agentId = agentId, modelName = modelName, content = content))
        }
        return panes
    }

    fun sendCommandToPane(paneIndex: Int, text: String) {
        viewModelScope.launch {
            if (!sshManager.isConnected()) {
                _errorMessage.value = "SSH未接続"
                return@launch
            }
            val target = "${agentsTarget()}.$paneIndex"
            val escaped = text.replace("'", "'\\''")
            // Send text and Enter SEPARATELY with 0.3s gap (Claude Code requirement)
            sshManager.execCommand("${Defaults.TMUX} send-keys -t $target '$escaped'")
            delay(300)
            sshManager.execCommand("${Defaults.TMUX} send-keys -t $target Enter")
            delay(1000)
            refreshAllPanes()
        }
    }

    fun execRateLimitCheck() {
        viewModelScope.launch {
            _rateLimitLoading.value = true
            _rateLimitResult.value = null
            val projectPath = prefs.getString(PrefsKeys.PROJECT_PATH, "") ?: ""
            if (projectPath.isBlank()) {
                _rateLimitLoading.value = false
                _rateLimitResult.value = "設定画面でプロジェクトパスを設定してください"
                return@launch
            }
            val safeProjectPath = projectPath.replace("'", "'\\''")
            val cmd = "rate_limit_script='$safeProjectPath/shogunate_mod/status/ratelimit_check.sh'; if [ ! -f \"\$rate_limit_script\" ]; then rate_limit_script='$safeProjectPath/scripts/ratelimit_check.sh'; fi; if [ ! -f \"\$rate_limit_script\" ]; then echo '使用量チェック script が見つかりません。Shogunate runtime のプロジェクトパスを確認してください。'; exit 0; fi; timeout 12s bash \"\$rate_limit_script\" 2>&1"
            val result = sshManager.execCommand(cmd)
            _rateLimitLoading.value = false
            _rateLimitResult.value = result.getOrElse { "SSH取得失敗: ${it.message}\ncmd: $cmd" }
        }
    }

    fun clearRateLimitResult() {
        _rateLimitResult.value = null
    }

    override fun onCleared() {
        super.onCleared()
        refreshJob?.cancel()
        reconnectJob?.cancel()
        // Do NOT disconnect the shared singleton SshManager here.
        // Tab navigation triggers onCleared, killing the connection for all ViewModels.
    }
}
