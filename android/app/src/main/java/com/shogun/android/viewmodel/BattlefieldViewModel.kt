package com.shogun.android.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.shogun.android.ssh.SshManager
import com.shogun.android.util.Defaults
import com.shogun.android.util.PrefsKeys
import com.shogun.android.util.ShogunateCampProfile
import com.shogun.android.util.ShogunateCampProfileStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

data class BattlefieldActionState(
    val running: Boolean = false,
    val success: Boolean = false,
    val message: String = ""
)

data class BattlefieldRuntimeInfo(
    val status: String = "unknown",
    val session: String = "",
    val daemonSession: String = "",
    val workspace: String = "",
    val dashboard: String = ""
)

data class BattlefieldHostItem(
    val campId: String,
    val name: String,
    val host: String,
    val port: String,
    val user: String,
    val online: Boolean = false,
    val message: String = "",
    val projectCount: Int = 0
) {
    val displayName: String
        get() = name.ifBlank { "$user@$host:$port" }
}

data class BattlefieldItem(
    val campId: String,
    val campName: String,
    val host: String,
    val port: String,
    val user: String,
    val id: String,
    val name: String,
    val path: String,
    val lastOpenedAt: Long,
    val runtime: BattlefieldRuntimeInfo,
    val sessionCount: Int,
    val currentSession: String
) {
    val key: String = "$campId:$id"
    val displayName: String = name.ifBlank { path.trimEnd('/').substringAfterLast('/') }
    val hostLabel: String = campName.ifBlank { "$user@$host:$port" }
}

data class BattlefieldSessionItem(
    val id: String,
    val title: String,
    val mode: String,
    val updatedAt: Long
)

data class BattlefieldRoleItem(
    val role: String,
    val pane: String,
    val cli: String,
    val model: String
)

data class BattlefieldMessageItem(
    val type: String,
    val time: String,
    val from: String,
    val to: String,
    val content: String
)

data class BattlefieldUiState(
    val hosts: List<BattlefieldHostItem> = emptyList(),
    val selectedHostId: String = "",
    val capabilitiesOk: Boolean = false,
    val projects: List<BattlefieldItem> = emptyList(),
    val selectedProjectId: String = "",
    val sessions: List<BattlefieldSessionItem> = emptyList(),
    val selectedSessionId: String = "",
    val roles: List<BattlefieldRoleItem> = emptyList(),
    val selectedRole: String = "shogun",
    val transcript: List<BattlefieldMessageItem> = emptyList()
) {
    val selectedHost: BattlefieldHostItem?
        get() = hosts.firstOrNull { it.campId == selectedHostId } ?: hosts.firstOrNull()
    val selectedProject: BattlefieldItem?
        get() = projects.firstOrNull { it.key == selectedProjectId }
            ?: projects.firstOrNull { it.campId == selectedHostId }
            ?: projects.firstOrNull()
}

class BattlefieldViewModel(application: Application) : AndroidViewModel(application) {

    private val prefs = application.getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)
    private val sshManager = SshManager.getInstance()
    private val campStore = ShogunateCampProfileStore(prefs)
    private val _uiState = MutableStateFlow(BattlefieldUiState())
    val uiState: StateFlow<BattlefieldUiState> = _uiState

    private val _actionState = MutableStateFlow(BattlefieldActionState())
    val actionState: StateFlow<BattlefieldActionState> = _actionState
    private var transcriptRefreshRunning = false

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _actionState.value = BattlefieldActionState(running = true, message = "PCの接続状態を確認中...")
            val profiles = campStore.profiles()
            if (profiles.isEmpty()) {
                _actionState.value = BattlefieldActionState(
                    running = false,
                    success = false,
                    message = "接続先PCがまだありません。設定タブでUSBまたは無線の接続を完了してください。"
                )
                return@launch
            }
            val hostItems = mutableListOf<BattlefieldHostItem>()
            val allProjects = mutableListOf<BattlefieldItem>()
            profiles.forEach { profile ->
                val connected = connectToProfile(profile)
                if (connected.isFailure) {
                    hostItems += hostItem(profile, online = false, message = "オフライン")
                    return@forEach
                }
                val capabilities = execJson("shogunate app capabilities --json")
                val list = execJson("shogunate battlefield list --json")
                if (capabilities.isFailure || list.isFailure) {
                    hostItems += hostItem(profile, online = false, message = "API未対応")
                    return@forEach
                }
                val projects = parseProjects(
                    array = list.getOrThrow().optJSONArray("projects") ?: JSONArray(),
                    profile = profile
                )
                allProjects += projects
                hostItems += hostItem(
                    profile = profile,
                    online = true,
                    message = "オンライン",
                    projectCount = projects.size
                )
            }
            val previousSelected = _uiState.value.selectedProjectId
            val activeCampId = campStore.activeProfile()?.id.orEmpty()
            val selectedHost = hostItems.firstOrNull { it.campId == _uiState.value.selectedHostId }?.campId
                ?: hostItems.firstOrNull { it.campId == activeCampId }?.campId
                ?: hostItems.firstOrNull { it.online }?.campId
                ?: hostItems.firstOrNull()?.campId
                ?: ""
            val selected = allProjects.firstOrNull { it.key == previousSelected }?.key
                ?: allProjects.firstOrNull { it.campId == selectedHost }?.key
                ?: allProjects.firstOrNull()?.key
                ?: ""
            _uiState.value = _uiState.value.copy(
                hosts = hostItems,
                selectedHostId = selectedHost,
                capabilitiesOk = hostItems.any { it.online },
                projects = allProjects,
                selectedProjectId = selected
            )
            if (selected.isNotBlank()) {
                refreshProjectDetails(selected, quiet = true)
            } else {
                val online = hostItems.count { it.online }
                _actionState.value = BattlefieldActionState(false, online > 0, "オンラインPC: $online / ${hostItems.size}。登録済み戦場はまだありません。")
            }
        }
    }

    fun selectProject(projectId: String) {
        val project = _uiState.value.projects.firstOrNull { it.key == projectId } ?: return
        _uiState.value = _uiState.value.copy(selectedHostId = project.campId, selectedProjectId = project.key)
        viewModelScope.launch {
            campStore.select(project.campId)?.let { connectToProfile(it) }
            refreshProjectDetails(project.key, quiet = false)
        }
    }

    fun selectHost(campId: String) {
        val selectedProject = _uiState.value.projects.firstOrNull { it.campId == campId }?.key.orEmpty()
        _uiState.value = _uiState.value.copy(selectedHostId = campId, selectedProjectId = selectedProject)
        viewModelScope.launch {
            campStore.select(campId)?.let { connectToProfile(it) }
            if (selectedProject.isNotBlank()) {
                refreshProjectDetails(selectedProject, quiet = false)
            } else {
                _actionState.value = BattlefieldActionState(false, true, "PCを選択しました。登録済み戦場がない場合はプロジェクトを登録してください。")
            }
        }
    }

    fun checkSelectedHost() {
        val host = _uiState.value.selectedHost ?: return
        viewModelScope.launch {
            _actionState.value = BattlefieldActionState(running = true, message = "${host.displayName} を確認中...")
            val profile = campStore.profiles().firstOrNull { it.id == host.campId }
            if (profile == null) {
                _actionState.value = BattlefieldActionState(false, false, "選択中PCが見つかりません。")
                return@launch
            }
            val connected = connectToProfile(profile)
            _actionState.value = if (connected.isSuccess) {
                BattlefieldActionState(false, true, "オンライン: ${host.displayName}")
            } else {
                BattlefieldActionState(false, false, "オフライン: ${host.displayName}")
            }
            refresh()
        }
    }

    fun selectRole(role: String) {
        _uiState.value = _uiState.value.copy(selectedRole = role.ifBlank { "shogun" })
    }

    fun selectSession(sessionId: String) {
        _uiState.value = _uiState.value.copy(selectedSessionId = sessionId)
        viewModelScope.launch {
            loadTranscript(_uiState.value.selectedProjectId)
        }
    }

    fun registerProject(path: String) {
        val normalized = path.trim().trimEnd('/')
        if (normalized.isBlank()) {
            _actionState.value = BattlefieldActionState(message = "登録するプロジェクトパスを入力してください。")
            return
        }
        viewModelScope.launch {
            _actionState.value = BattlefieldActionState(running = true, message = "戦場を登録中...")
            val profile = selectedProfile()
            if (profile == null) {
                _actionState.value = BattlefieldActionState(false, false, "登録先PCを選んでください。")
                return@launch
            }
            val connected = connectToProfile(profile)
            if (connected.isFailure) {
                _actionState.value = BattlefieldActionState(false, false, "選択中PCへ接続できません。")
                return@launch
            }
            val result = execPlain("if [ -d ${Defaults.shellQuote(normalized)} ]; then shogunate projects add ${Defaults.shellQuote(normalized)} --select; else echo __PROJECT_MISSING__; fi")
            if (result.isFailure || result.getOrDefault("").contains("__PROJECT_MISSING__")) {
                _actionState.value = BattlefieldActionState(false, false, "プロジェクトが見つかりません: $normalized")
                return@launch
            }
            _actionState.value = BattlefieldActionState(false, true, "登録しました: $normalized")
            refresh()
        }
    }

    fun startSelected(newSession: Boolean) {
        val project = _uiState.value.selectedProject ?: return
        viewModelScope.launch {
            _actionState.value = BattlefieldActionState(running = true, message = if (newSession) "新しく開始中..." else "続きから起動中...")
            val profile = profileForProject(project)
            if (profile == null || connectToProfile(profile).isFailure) {
                _actionState.value = BattlefieldActionState(false, false, "対象PCへ接続できません。")
                return@launch
            }
            val mode = if (newSession) "--new" else "--resume"
            val result = execPlain(
                "log=\"/tmp/shogunate-app-start-\$\$.log\"; " +
                    "nohup sh -lc ${Defaults.shellQuote("shogunate battlefield start ${project.id} $mode --json")} >\"\$log\" 2>&1 & " +
                    "echo __START_REQUESTED__; echo LOG=\"\$log\""
            )
            if (result.isFailure || !result.getOrDefault("").contains("__START_REQUESTED__")) {
                _actionState.value = BattlefieldActionState(false, false, "起動要求に失敗しました。")
                return@launch
            }
            delay(1800)
            _actionState.value = BattlefieldActionState(false, true, if (newSession) "新規チャットで起動要求を送りました。" else "続きから起動要求を送りました。")
            refresh()
        }
    }

    fun stopSelected() {
        val project = _uiState.value.selectedProject ?: return
        viewModelScope.launch {
            _actionState.value = BattlefieldActionState(running = true, message = "戦場を終了中...")
            val profile = profileForProject(project)
            if (profile == null || connectToProfile(profile).isFailure) {
                _actionState.value = BattlefieldActionState(false, false, "対象PCへ接続できません。")
                return@launch
            }
            val result = execJson("shogunate battlefield stop ${project.id} --json")
            _actionState.value = if (result.isSuccess) {
                BattlefieldActionState(false, true, "終了しました: ${project.displayName}")
            } else {
                BattlefieldActionState(false, false, "終了できませんでした。")
            }
            refresh()
        }
    }

    fun createSession(title: String = "") {
        val project = _uiState.value.selectedProject ?: return
        viewModelScope.launch {
            val profile = profileForProject(project)
            if (profile == null || connectToProfile(profile).isFailure) {
                _actionState.value = BattlefieldActionState(false, false, "対象PCへ接続できません。")
                return@launch
            }
            val command = buildString {
                append("shogunate battlefield session-create ${project.id} --json")
                if (title.isNotBlank()) append(" --title ${Defaults.shellQuote(title)}")
            }
            val result = execJson(command)
            if (result.isSuccess) {
                _actionState.value = BattlefieldActionState(false, true, "新しい会話を作成しました。")
                refreshProjectDetails(project.key, quiet = true)
            } else {
                _actionState.value = BattlefieldActionState(false, false, "会話を作成できませんでした。")
            }
        }
    }

    fun sendMessage(text: String, onSent: () -> Unit = {}) {
        val project = _uiState.value.selectedProject ?: return
        val message = text.trim()
        if (message.isBlank()) {
            _actionState.value = BattlefieldActionState(message = "送信する内容を入力してください。")
            return
        }
        viewModelScope.launch {
            val role = _uiState.value.selectedRole.ifBlank { "shogun" }
            _actionState.value = BattlefieldActionState(running = true, message = "${role}へ送信中...")
            val profile = profileForProject(project)
            if (profile == null || connectToProfile(profile).isFailure) {
                _actionState.value = BattlefieldActionState(false, false, "対象PCへ接続できません。")
                return@launch
            }
            val result = execJson("shogunate battlefield send ${project.id} ${Defaults.shellQuote(message)} --role ${Defaults.shellQuote(role)} --json")
            if (result.isSuccess) {
                _actionState.value = BattlefieldActionState(false, true, "${role}へ送りました。")
                onSent()
                loadTranscript(project.key)
            } else {
                _actionState.value = BattlefieldActionState(false, false, "送信できませんでした。戦場が起動中か確認してください。")
            }
        }
    }

    fun refreshTranscriptOnly() {
        val projectKey = _uiState.value.selectedProjectId
        if (projectKey.isBlank() || _uiState.value.selectedSessionId.isBlank() || transcriptRefreshRunning) return
        viewModelScope.launch {
            transcriptRefreshRunning = true
            try {
                loadTranscript(projectKey)
            } finally {
                transcriptRefreshRunning = false
            }
        }
    }

    fun pollTranscript() {
        if (_actionState.value.running) return
        refreshTranscriptOnly()
    }

    private suspend fun refreshProjectDetails(projectKey: String, quiet: Boolean) {
        val project = _uiState.value.projects.firstOrNull { it.key == projectKey } ?: return
        val profile = profileForProject(project) ?: return
        if (connectToProfile(profile).isFailure) {
            if (!quiet) _actionState.value = BattlefieldActionState(false, false, "対象PCへ接続できません。")
            return
        }
        if (!quiet) _actionState.value = BattlefieldActionState(running = true, message = "戦場の詳細を取得中...")
        val sessionsResult = execJson("shogunate battlefield sessions ${project.id} --json")
        val rolesResult = execJson("shogunate battlefield roles ${project.id} --json")
        val sessionsPayload = sessionsResult.getOrNull()
        val rolesPayload = rolesResult.getOrNull()
        val sessions = parseSessions(sessionsPayload?.optJSONArray("sessions") ?: JSONArray())
        val selectedSession = sessionsPayload?.optString("current").orEmpty()
            .ifBlank { sessions.firstOrNull()?.id.orEmpty() }
        val roles = parseRoles(rolesPayload?.optJSONArray("roles") ?: JSONArray())
        val selectedRole = when {
            _uiState.value.selectedRole.isBlank() -> "shogun"
            roles.isEmpty() -> _uiState.value.selectedRole
            roles.any { it.role == _uiState.value.selectedRole } -> _uiState.value.selectedRole
            else -> "shogun"
        }
        _uiState.value = _uiState.value.copy(
            sessions = sessions,
            selectedSessionId = selectedSession,
            roles = roles,
            selectedRole = selectedRole
        )
        loadTranscript(project.key)
        if (!quiet) _actionState.value = BattlefieldActionState(false, true, "戦場を選択しました。")
    }

    private suspend fun loadTranscript(projectKey: String) {
        if (projectKey.isBlank()) return
        val project = _uiState.value.projects.firstOrNull { it.key == projectKey } ?: return
        val profile = profileForProject(project) ?: return
        if (connectToProfile(profile).isFailure) return
        val session = _uiState.value.selectedSessionId
        val command = buildString {
            append("shogunate battlefield transcript ${project.id} --json")
            if (session.isNotBlank()) append(" --session ${Defaults.shellQuote(session)}")
        }
        val payload = execJson(command).getOrNull() ?: return
        _uiState.value = _uiState.value.copy(
            transcript = parseMessages(payload.optJSONArray("messages") ?: JSONArray())
        )
    }

    private fun selectedProfile(): ShogunateCampProfile? {
        val selectedHost = _uiState.value.selectedHostId
        return campStore.profiles().firstOrNull { it.id == selectedHost }
            ?: campStore.activeProfile()
            ?: campStore.profiles().firstOrNull()
    }

    private fun profileForProject(project: BattlefieldItem): ShogunateCampProfile? {
        return campStore.profiles().firstOrNull { it.id == project.campId }
    }

    private suspend fun connectToProfile(profile: ShogunateCampProfile): Result<Unit> {
        val port = profile.port.toIntOrNull() ?: return Result.failure(IllegalArgumentException("SSH port is invalid"))
        if (profile.host.isBlank() || profile.user.isBlank()) {
            return Result.failure(IllegalStateException("SSH host/user is blank"))
        }
        return sshManager.connect(profile.host, port, profile.user, profile.keyPath, profile.password)
    }

    private fun hostItem(
        profile: ShogunateCampProfile,
        online: Boolean,
        message: String,
        projectCount: Int = 0
    ): BattlefieldHostItem {
        return BattlefieldHostItem(
            campId = profile.id,
            name = profile.displayName,
            host = profile.host,
            port = profile.port,
            user = profile.user,
            online = online,
            message = message,
            projectCount = projectCount
        )
    }

    private suspend fun execJson(command: String): Result<JSONObject> {
        return execPlain(command).mapCatching { output ->
            JSONObject(extractJsonObject(output))
        }
    }

    private suspend fun execPlain(command: String): Result<String> {
        return sshManager.execCommand("${remotePathSetup()}; if ! command -v shogunate >/dev/null 2>&1; then echo __SHOGUNATE_MISSING__; exit 0; fi; $command")
    }

    private fun remotePathSetup(): String {
        return "export PATH=\"\$HOME/.local/bin:\$HOME/bin:/usr/local/bin:/usr/bin:/bin:\$PATH\"; " +
            "for node_bin in \"\$HOME\"/.nvm/versions/node/*/bin; do [ -d \"\$node_bin\" ] && export PATH=\"\$node_bin:\$PATH\"; done"
    }

    private fun extractJsonObject(output: String): String {
        val start = output.indexOf('{')
        val end = output.lastIndexOf('}')
        require(start >= 0 && end >= start) { "JSON output not found: ${output.take(120)}" }
        return output.substring(start, end + 1)
    }

    private fun parseProjects(array: JSONArray, profile: ShogunateCampProfile): List<BattlefieldItem> {
        return (0 until array.length()).mapNotNull { index ->
            val obj = array.optJSONObject(index) ?: return@mapNotNull null
            val runtime = obj.optJSONObject("runtime") ?: JSONObject()
            val sessions = obj.optJSONObject("sessions") ?: JSONObject()
            BattlefieldItem(
                campId = profile.id,
                campName = profile.displayName,
                host = profile.host,
                port = profile.port,
                user = profile.user,
                id = obj.optString("id"),
                name = obj.optString("name"),
                path = obj.optString("path"),
                lastOpenedAt = obj.optLong("last_opened_at", 0),
                runtime = BattlefieldRuntimeInfo(
                    status = runtime.optString("status", "unknown"),
                    session = runtime.optString("session"),
                    daemonSession = runtime.optString("daemon_session"),
                    workspace = runtime.optString("workspace"),
                    dashboard = runtime.optString("dashboard")
                ),
                sessionCount = sessions.optInt("count", 0),
                currentSession = sessions.optString("current")
            )
        }
    }

    private fun parseSessions(array: JSONArray): List<BattlefieldSessionItem> {
        return (0 until array.length()).mapNotNull { index ->
            val obj = array.optJSONObject(index) ?: return@mapNotNull null
            BattlefieldSessionItem(
                id = obj.optString("id"),
                title = obj.optString("title").ifBlank { obj.optString("id") },
                mode = obj.optString("mode"),
                updatedAt = obj.optLong("updated_at", 0)
            )
        }
    }

    private fun parseRoles(array: JSONArray): List<BattlefieldRoleItem> {
        val roles = (0 until array.length()).mapNotNull { index ->
            val obj = array.optJSONObject(index) ?: return@mapNotNull null
            BattlefieldRoleItem(
                role = obj.optString("role"),
                pane = obj.optString("pane"),
                cli = obj.optString("cli"),
                model = obj.optString("model")
            )
        }.filter { it.role.isNotBlank() }
        return if (roles.any { it.role == "shogun" }) roles else listOf(BattlefieldRoleItem("shogun", "", "", "")) + roles
    }

    private fun parseMessages(array: JSONArray): List<BattlefieldMessageItem> {
        return (0 until array.length()).mapNotNull { index ->
            val obj = array.optJSONObject(index) ?: return@mapNotNull null
            BattlefieldMessageItem(
                type = obj.optString("type"),
                time = obj.optString("time"),
                from = obj.optString("from"),
                to = obj.optString("to"),
                content = obj.optString("content")
            )
        }
    }
}
