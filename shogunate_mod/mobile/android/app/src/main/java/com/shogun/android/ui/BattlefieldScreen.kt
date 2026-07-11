package com.shogun.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shogun.android.ui.theme.Kinpaku
import com.shogun.android.ui.theme.Matsuba
import com.shogun.android.ui.theme.Shikkoku
import com.shogun.android.ui.theme.Shuaka
import com.shogun.android.ui.theme.Sumi
import com.shogun.android.ui.theme.TextMuted
import com.shogun.android.ui.theme.TextSecondary
import com.shogun.android.ui.theme.Tetsukon
import com.shogun.android.viewmodel.BattlefieldHostItem
import com.shogun.android.viewmodel.BattlefieldItem
import com.shogun.android.viewmodel.BattlefieldMessageItem
import com.shogun.android.viewmodel.BattlefieldRoleItem
import com.shogun.android.viewmodel.BattlefieldSessionItem
import com.shogun.android.viewmodel.BattlefieldViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun BattlefieldScreen(viewModel: BattlefieldViewModel = viewModel()) {
    val uiState by viewModel.uiState.collectAsState()
    val actionState by viewModel.actionState.collectAsState()
    var projectPath by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }

    LaunchedEffect(uiState.selectedProjectId, uiState.selectedSessionId) {
        if (uiState.selectedProjectId.isBlank() || uiState.selectedSessionId.isBlank()) return@LaunchedEffect
        while (isActive) {
            delay(5000)
            viewModel.pollTranscript()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Shikkoku)
            .padding(14.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("司令台", style = MaterialTheme.typography.titleLarge, color = Kinpaku)
                Text(
                    text = uiState.selectedHost?.let {
                        "${it.displayName} / ${if (it.online) "オンライン" else "オフライン"}"
                    } ?: "PC未登録",
                    color = TextSecondary,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = { viewModel.refresh() }, enabled = !actionState.running) {
                Icon(Icons.Default.Refresh, contentDescription = "更新", tint = Kinpaku)
            }
        }

        StatusLine(actionState.message, actionState.success)

        HostListCard(
            hosts = uiState.hosts,
            selectedHostId = uiState.selectedHostId,
            onSelect = { viewModel.selectHost(it) },
            onCheck = { viewModel.checkSelectedHost() },
            running = actionState.running
        )

        RegisterProjectCard(
            path = projectPath,
            onPathChange = { projectPath = it },
            onRegister = { viewModel.registerProject(projectPath) },
            running = actionState.running
        )

        BattlefieldListCard(
            projects = uiState.projects.filter { it.campId == uiState.selectedHostId },
            selectedId = uiState.selectedProjectId,
            onSelect = { viewModel.selectProject(it) }
        )

        uiState.selectedProject?.let { project ->
            BattlefieldControlCard(
                project = project,
                running = actionState.running,
                onResume = { viewModel.startSelected(newSession = false) },
                onNew = { viewModel.startSelected(newSession = true) },
                onStop = { viewModel.stopSelected() }
            )

            SessionsCard(
                sessions = uiState.sessions,
                selectedSessionId = uiState.selectedSessionId,
                onSelect = { viewModel.selectSession(it) },
                onCreate = { viewModel.createSession() }
            )

            RoleChatCard(
                roles = uiState.roles,
                selectedRole = uiState.selectedRole,
                message = message,
                transcript = uiState.transcript,
                running = actionState.running,
                onRoleSelect = { viewModel.selectRole(it) },
                onMessageChange = { message = it },
                onSend = {
                    viewModel.sendMessage(message) { message = "" }
                }
            )
        }
    }
}

@Composable
private fun StatusLine(message: String, success: Boolean) {
    if (message.isBlank()) return
    Text(
        text = message,
        color = if (success) Color(0xFF9CCC65) else Color(0xFFFFB74D),
        fontFamily = FontFamily.Monospace,
        fontSize = 12.sp,
        modifier = Modifier.fillMaxWidth()
    )
}

@Composable
private fun HostListCard(
    hosts: List<BattlefieldHostItem>,
    selectedHostId: String,
    onSelect: (String) -> Unit,
    onCheck: () -> Unit,
    running: Boolean
) {
    AppCard {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("PC", style = MaterialTheme.typography.titleMedium, color = Kinpaku)
            OutlinedButton(
                onClick = onCheck,
                enabled = !running && selectedHostId.isNotBlank(),
                shape = RoundedCornerShape(4.dp)
            ) {
                Text("生存チェック")
            }
        }
        if (hosts.isEmpty()) {
            Text("接続先PCはまだありません。設定タブでUSBまたは無線接続を追加してください。", color = TextSecondary, fontSize = 12.sp)
        } else {
            hosts.forEach { host ->
                HostRow(
                    host = host,
                    selected = host.campId == selectedHostId,
                    onClick = { onSelect(host.campId) }
                )
            }
        }
    }
}

@Composable
private fun HostRow(host: BattlefieldHostItem, selected: Boolean, onClick: () -> Unit) {
    val statusColor = if (host.online) Matsuba else TextMuted
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(if (selected) Tetsukon else Color.Transparent, RoundedCornerShape(4.dp))
            .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(host.displayName, color = if (selected) Kinpaku else TextSecondary, fontSize = 15.sp)
            Text(if (host.online) "オンライン" else "オフライン", color = statusColor, fontSize = 12.sp)
        }
        Text("${host.user}@${host.host}:${host.port}", color = TextMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text("${host.projectCount} projects / ${host.message}", color = TextMuted, fontSize = 11.sp)
    }
}

@Composable
private fun RegisterProjectCard(
    path: String,
    onPathChange: (String) -> Unit,
    onRegister: () -> Unit,
    running: Boolean
) {
    AppCard {
        Text("PC上のプロジェクトを登録", style = MaterialTheme.typography.titleMedium, color = Kinpaku)
        OutlinedTextField(
            value = path,
            onValueChange = onPathChange,
            label = { Text("プロジェクトパス") },
            placeholder = { Text("/path/to/my-project") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        OutlinedButton(
            onClick = onRegister,
            enabled = !running,
            shape = RoundedCornerShape(4.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.Add, contentDescription = null)
            Text("登録")
        }
    }
}

@Composable
private fun BattlefieldListCard(
    projects: List<BattlefieldItem>,
    selectedId: String,
    onSelect: (String) -> Unit
) {
    AppCard {
        Text("戦場", style = MaterialTheme.typography.titleMedium, color = Kinpaku)
        if (projects.isEmpty()) {
            Text("登録済みの戦場はありません。PCで shogunate を起動するか、上から登録してください。", color = TextSecondary, fontSize = 12.sp)
        } else {
            projects.forEach { project ->
                BattlefieldRow(
                    project = project,
                    selected = project.key == selectedId,
                    onClick = { onSelect(project.key) }
                )
            }
        }
    }
}

@Composable
private fun BattlefieldRow(project: BattlefieldItem, selected: Boolean, onClick: () -> Unit) {
    val statusColor = when (project.runtime.status) {
        "running" -> Matsuba
        "stopped" -> TextMuted
        else -> Kinpaku
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(if (selected) Tetsukon else Color.Transparent, RoundedCornerShape(4.dp))
            .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(project.displayName, color = if (selected) Kinpaku else TextSecondary, fontSize = 15.sp)
            Text(project.runtime.status, color = statusColor, fontSize = 12.sp)
        }
        Text(project.path, color = TextMuted, fontSize = 11.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(project.hostLabel, color = TextMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (project.currentSession.isNotBlank() || project.sessionCount > 0) {
            Text("sessions: ${project.sessionCount}", color = TextMuted, fontSize = 11.sp)
        }
    }
}

@Composable
private fun BattlefieldControlCard(
    project: BattlefieldItem,
    running: Boolean,
    onResume: () -> Unit,
    onNew: () -> Unit,
    onStop: () -> Unit
) {
    AppCard {
        Text(project.displayName, style = MaterialTheme.typography.titleMedium, color = Kinpaku)
        Text(project.runtime.session, color = TextMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = onResume,
                enabled = !running,
                shape = RoundedCornerShape(4.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Matsuba, contentColor = Color.White),
                modifier = Modifier.weight(1f)
            ) {
                Text("続き")
            }
            OutlinedButton(
                onClick = onNew,
                enabled = !running,
                shape = RoundedCornerShape(4.dp),
                modifier = Modifier.weight(1f)
            ) {
                Text("新規")
            }
            OutlinedButton(
                onClick = onStop,
                enabled = !running,
                shape = RoundedCornerShape(4.dp),
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.Default.PowerSettingsNew, contentDescription = null)
                Text("終了")
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SessionsCard(
    sessions: List<BattlefieldSessionItem>,
    selectedSessionId: String,
    onSelect: (String) -> Unit,
    onCreate: () -> Unit
) {
    AppCard {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("会話", style = MaterialTheme.typography.titleMedium, color = Kinpaku)
            IconButton(onClick = onCreate) {
                Icon(Icons.Default.Add, contentDescription = "新規会話", tint = Kinpaku)
            }
        }
        if (sessions.isEmpty()) {
            Text("会話履歴はまだありません。新規を押すか、戦場を起動してください。", color = TextSecondary, fontSize = 12.sp)
        } else {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                sessions.take(8).forEach { session ->
                    FilterChip(
                        selected = session.id == selectedSessionId,
                        onClick = { onSelect(session.id) },
                        label = { Text(session.title, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RoleChatCard(
    roles: List<BattlefieldRoleItem>,
    selectedRole: String,
    message: String,
    transcript: List<BattlefieldMessageItem>,
    running: Boolean,
    onRoleSelect: (String) -> Unit,
    onMessageChange: (String) -> Unit,
    onSend: () -> Unit
) {
    val listState = rememberLazyListState()

    LaunchedEffect(transcript.size) {
        if (transcript.isNotEmpty()) {
            listState.animateScrollToItem(transcript.lastIndex)
        }
    }

    AppCard {
        Text("役職に話す", style = MaterialTheme.typography.titleMedium, color = Kinpaku)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            roles.distinctBy { it.role }.forEach { role ->
                AssistChip(
                    onClick = { onRoleSelect(role.role) },
                    label = { Text(if (role.role == selectedRole) "選択中: ${roleDisplayName(role.role)}" else roleDisplayName(role.role)) }
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Bottom
        ) {
            OutlinedTextField(
                value = message,
                onValueChange = onMessageChange,
                label = { Text("${roleDisplayName(selectedRole.ifBlank { "shogun" })} へ送信") },
                modifier = Modifier.weight(1f),
                enabled = !running,
                minLines = 1,
                maxLines = 4
            )
            IconButton(
                onClick = onSend,
                enabled = !running && message.isNotBlank(),
                modifier = Modifier
                    .size(48.dp)
                    .background(if (!running && message.isNotBlank()) Shuaka else Color(0xFF5A3A3A), CircleShape)
            ) {
                Icon(Icons.Default.Send, contentDescription = "送信", tint = if (!running && message.isNotBlank()) Color.White else TextMuted)
            }
        }
        Text("会話履歴", color = Kinpaku, fontSize = 13.sp)
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxWidth()
                .height(320.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (transcript.isEmpty()) {
                item {
                    Text("まだメッセージはありません。", color = TextMuted, fontSize = 12.sp)
                }
            } else {
                items(transcript) { item ->
                    TranscriptMessageRow(item)
                }
            }
        }
    }
}

@Composable
private fun TranscriptMessageRow(item: BattlefieldMessageItem) {
    when {
        item.from == "lord" || item.type == "user_message" -> LordMessageBubble(item.content)
        item.type == "role_message" -> RoleMessageBubble(item)
        else -> SystemMessageLine(item)
    }
}

@Composable
private fun LordMessageBubble(content: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Text(
            text = content,
            color = Color.White,
            fontSize = 13.sp,
            modifier = Modifier
                .widthIn(max = 292.dp)
                .background(Shuaka, RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp, bottomStart = 12.dp, bottomEnd = 4.dp))
                .padding(horizontal = 12.dp, vertical = 9.dp)
        )
    }
}

@Composable
private fun RoleMessageBubble(item: BattlefieldMessageItem) {
    val time = transcriptTimeLabel(item.time)
    val label = listOf(roleDisplayName(item.from), time).filter { it.isNotBlank() }.joinToString(" ")
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Start) {
        Column(
            modifier = Modifier
                .widthIn(max = 292.dp)
                .background(
                    Color(0xFF3A3A3A),
                    RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp, bottomStart = 4.dp, bottomEnd = 12.dp)
                )
                .padding(horizontal = 12.dp, vertical = 9.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(label, color = Kinpaku, fontSize = 12.sp)
            Text(item.content, color = TextSecondary, fontSize = 13.sp)
        }
    }
}

@Composable
private fun SystemMessageLine(item: BattlefieldMessageItem) {
    val status = when {
        item.content.isNotBlank() -> item.content
        item.type == "delivery_status" && item.to.isNotBlank() -> "✓ ${roleDisplayName(item.to)}へ配送済み"
        item.type.isNotBlank() -> item.type
        else -> ""
    }
    if (status.isBlank()) return
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
        Text(status, color = TextMuted, fontSize = 11.sp)
    }
}

@Composable
private fun AppCard(content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Sumi),
        shape = RoundedCornerShape(6.dp)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content
        )
    }
}
