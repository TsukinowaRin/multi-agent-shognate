package com.shogun.android.viewmodel

import android.app.Application
import android.content.Context
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.shogun.android.SshForegroundService
import com.shogun.android.ssh.SshManager
import com.shogun.android.util.Defaults
import com.shogun.android.util.PrefsKeys
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

    private val _draftText = MutableStateFlow("")
    val draftText: StateFlow<String> = _draftText

    private var refreshJob: Job? = null
    private var reconnectJob: Job? = null
    @Volatile private var paused = false

    private fun targetAssignment(): String {
        val session = prefs.getString(PrefsKeys.SHOGUN_SESSION, Defaults.SHOGUN_SESSION) ?: Defaults.SHOGUN_SESSION
        return Defaults.shogunTargetAssignment(session)
    }

    private fun captureCommand(): String =
        "${targetAssignment()}; if [ -n \"\$target\" ]; then ${Defaults.TMUX} capture-pane -t \"\$target\" -p -e -S -500; else echo __SHOGUNATE_TARGET_MISSING__; fi"

    private fun applyCaptureResult(output: String) {
        if (output.contains("__SHOGUNATE_TARGET_MISSING__")) {
            _paneContent.value = ""
            _errorMessage.value = "将軍 pane が見つかりません。設定の将軍 target と Shogunate runtime を確認してください。"
        } else {
            _paneContent.value = trimTrailingBlankLines(output)
            _errorMessage.value = null
        }
    }

    private fun trimTrailingBlankLines(output: String): String =
        output.lines().dropLastWhile { it.isBlank() }.joinToString("\n")

    fun setDraftText(text: String) {
        _draftText.value = text
    }

    fun clearDraftText() {
        _draftText.value = ""
    }

    fun pauseRefresh() { paused = true }
    fun resumeRefresh() {
        paused = false
        viewModelScope.launch {
            if (!sshManager.isConnected()) {
                connectFromPrefs()
                return@launch
            }
            val result = sshManager.execCommand(captureCommand())
            if (result.isSuccess) {
                applyCaptureResult(result.getOrDefault(""))
            } else {
                _isConnected.value = false
                _errorMessage.value = "再接続中: ${result.exceptionOrNull()?.message}"
                startReconnect()
            }
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
        if (host.isBlank() || user.isBlank()) {
            _isConnected.value = false
            _errorMessage.value = "設定画面でSSHホスト、ポート、ユーザーを設定してください"
            return
        }
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
                startAutoRefresh()
            } else {
                _errorMessage.value = "接続失敗: ${result.exceptionOrNull()?.message}"
                startReconnect()
            }
        }
    }

    private fun startAutoRefresh() {
        refreshJob?.cancel()
        refreshJob = viewModelScope.launch {
            while (isActive) {
                if (!paused && sshManager.isConnected()) {
                    val result = sshManager.execCommand(captureCommand())
                    if (result.isSuccess) {
                        applyCaptureResult(result.getOrDefault(""))
                    } else {
                        _isConnected.value = false
                        _errorMessage.value = "再接続中: ${result.exceptionOrNull()?.message}"
                        startReconnect()
                    }
                }
                delay(3000)
            }
        }
    }

    fun sendCommand(text: String) {
        viewModelScope.launch {
            val setup = targetAssignment()
            val current = sshManager.execCommand(captureCommand())
            if (current.isSuccess && isShogunPaneBusyOutput(current.getOrDefault(""))) {
                applyCaptureResult(current.getOrDefault(""))
                return@launch
            }
            if (current.isSuccess && isShogunComposerDirtyOutput(current.getOrDefault(""))) {
                applyCaptureResult(current.getOrDefault(""))
                sshManager.execCommand("$setup; [ -n \"\$target\" ] && ${Defaults.TMUX} send-keys -t \"\$target\" C-c")
                delay(200)
            }
            val quotedText = Defaults.shellQuote(text)
            // Send text and Enter SEPARATELY with 0.3s gap (Claude Code requirement)
            sshManager.execCommand("$setup; [ -n \"\$target\" ] && ${Defaults.TMUX} send-keys -t \"\$target\" $quotedText")
            delay(300)
            sshManager.execCommand("$setup; [ -n \"\$target\" ] && ${Defaults.TMUX} send-keys -t \"\$target\" Enter")
            delay(1500)
            if (sshManager.isConnected()) {
                val result = sshManager.execCommand(captureCommand())
                if (result.isSuccess) {
                    applyCaptureResult(result.getOrDefault(""))
                }
            }
        }
    }

    fun sendRawKey(key: String) {
        viewModelScope.launch {
            val setup = targetAssignment()
            val tmuxKey = when (key) {
                "\n" -> "Enter"
                "\u0003", "C-c" -> "C-c"
                "\u0002", "C-b" -> "C-b"
                "\u001b[A", "Up" -> "Up"
                "\u001b[B", "Down" -> "Down"
                "\t", "Tab" -> "Tab"
                "\u001b", "Escape", "ESC" -> "Escape"
                "\u000f", "C-o" -> "C-o"
                "\u0004", "C-d" -> "C-d"
                else -> null
            }
            val command = if (tmuxKey != null) {
                "$setup; [ -n \"\$target\" ] && ${Defaults.TMUX} send-keys -t \"\$target\" $tmuxKey"
            } else {
                "$setup; [ -n \"\$target\" ] && ${Defaults.TMUX} send-keys -t \"\$target\" -l ${Defaults.shellQuote(key)}"
            }
            sshManager.execCommand(command)
            delay(300)
            if (sshManager.isConnected()) {
                val result = sshManager.execCommand(captureCommand())
                if (result.isSuccess) {
                    applyCaptureResult(result.getOrDefault(""))
                }
            }
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

    override fun onCleared() {
        super.onCleared()
        refreshJob?.cancel()
        reconnectJob?.cancel()
    }

    private fun isShogunPaneBusyOutput(output: String): Boolean =
        output.lines().any {
            val line = stripTerminalControl(it).trim()
            line.startsWith("◦ Working") || line.contains("esc to interrupt")
        }

    private fun isShogunComposerDirtyOutput(output: String): Boolean {
        var dirty = false
        for (sourceLine in output.lines()) {
            val line = stripTerminalControl(sourceLine).trim()
            if (line.isBlank() || isTerminalNoiseLine(line)) continue
            if (line.startsWith("◦ Working") || line.contains("esc to interrupt") || line.startsWith("• ")) {
                dirty = false
                continue
            }
            if (line.startsWith("› ")) {
                val prompt = line.removePrefix("› ").trim()
                dirty = prompt.isNotBlank() && !prompt.startsWith("【初動命令】")
            }
        }
        return dirty
    }

    private fun stripTerminalControl(text: String): String =
        text.replace(Regex("\\u001B\\[[0-9;?]*[ -/]*[@-~]"), "")

    private fun isTerminalNoiseLine(line: String): Boolean =
        line.all { it in "─━═ │┃┌┐└┘╭╮╰╯┏┓┗┛╔╗╚╝╠╣╦╩╬+-_ " } ||
            line.startsWith("╭") ||
            line.startsWith("╰") ||
            line.startsWith("│") ||
            line.startsWith("Tip:") ||
            line.startsWith("model:") ||
            line.startsWith("directory:") ||
            line.startsWith("permissions:") ||
            line.startsWith("gpt-")
}
