package com.shogun.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.shogun.android.ui.theme.*
import com.shogun.android.util.ConnectionProfiles
import com.shogun.android.util.Defaults
import com.shogun.android.util.PrefsKeys
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shogun.android.util.AppLogger
import com.shogun.android.viewmodel.SettingsViewModel
import java.io.File

@Composable
fun SettingsScreen(settingsViewModel: SettingsViewModel = viewModel()) {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences(PrefsKeys.PREFS_NAME, Context.MODE_PRIVATE)
    val updateLoading by settingsViewModel.updateLoading.collectAsState()
    val updateResult by settingsViewModel.updateResult.collectAsState()

    var host by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_HOST, Defaults.SSH_HOST) ?: Defaults.SSH_HOST) }
    var port by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_PORT, Defaults.SSH_PORT_STR) ?: Defaults.SSH_PORT_STR) }
    var user by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_USER, "") ?: "") }
    var keyPath by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_KEY_PATH, "") ?: "") }
    var password by remember { mutableStateOf(prefs.getString(PrefsKeys.SSH_PASSWORD, "") ?: "") }
    var projectPath by remember { mutableStateOf(prefs.getString(PrefsKeys.PROJECT_PATH, Defaults.PROJECT_PATH) ?: Defaults.PROJECT_PATH) }
    var shogunSession by remember { mutableStateOf(prefs.getString(PrefsKeys.SHOGUN_SESSION, Defaults.SHOGUN_SESSION) ?: Defaults.SHOGUN_SESSION) }
    var agentsSession by remember { mutableStateOf(prefs.getString(PrefsKeys.AGENTS_SESSION, Defaults.AGENTS_SESSION) ?: Defaults.AGENTS_SESSION) }

    var saved by remember { mutableStateOf(false) }
    var tapCount by remember { mutableIntStateOf(0) }
    var showDebugLog by remember { mutableStateOf(false) }
    val pickSshKeyLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult

        runCatching { copySshKeyToAppStorage(context, uri) }
            .onSuccess { importedPath ->
                keyPath = importedPath
                saved = false
                Toast.makeText(context, "秘密鍵をアプリ領域へコピーしたでござる", Toast.LENGTH_SHORT).show()
            }
            .onFailure { error ->
                Toast.makeText(context, "秘密鍵取込失敗: ${error.message}", Toast.LENGTH_LONG).show()
            }
    }

    // Debug log dialog
    if (showDebugLog) {
        DebugLogDialog(onDismiss = { showDebugLog = false })
    }

    val saveSettings = {
        prefs.edit()
            .putString(PrefsKeys.SSH_HOST, host)
            .putString(PrefsKeys.SSH_PORT, port)
            .putString(PrefsKeys.SSH_USER, user)
            .putString(PrefsKeys.SSH_KEY_PATH, keyPath)
            .putString(PrefsKeys.SSH_PASSWORD, password)
            .putString(PrefsKeys.PROJECT_PATH, projectPath)
            .putString(PrefsKeys.SHOGUN_SESSION, shogunSession)
            .putString(PrefsKeys.AGENTS_SESSION, agentsSession)
            .apply()
        saved = true
    }

    val importConnectionProfileFromClipboard = {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
        val profile = ConnectionProfiles.parse(text)
        if (profile == null) {
            Toast.makeText(context, "接続プロファイルを読み取れません", Toast.LENGTH_LONG).show()
        } else {
            host = profile.host
            port = profile.port
            user = profile.user
            if (profile.projectPath.isNotBlank()) projectPath = profile.projectPath
            shogunSession = profile.shogunSession
            agentsSession = profile.agentsSession
            saved = false
            Toast.makeText(context, "接続プロファイルを反映しました", Toast.LENGTH_SHORT).show()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Shikkoku)
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            "SSH設定",
            style = MaterialTheme.typography.titleLarge,
            color = Kinpaku,
            modifier = Modifier.clickable {
                tapCount++
                if (tapCount >= 7) {
                    showDebugLog = true
                    tapCount = 0
                }
            }
        )

        Text("かんたん接続", style = MaterialTheme.typography.titleMedium, color = Kinpaku)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = {
                    port = "22"
                    saved = false
                },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(4.dp)
            ) {
                Text("Tailscale")
            }
            OutlinedButton(
                onClick = {
                    host = "127.0.0.1"
                    port = "2222"
                    saved = false
                },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(4.dp)
            ) {
                Text("USB")
            }
        }
        Text(
            "Tailscale は PC の 100.x IP をホストへ入力。USB は PC で adb reverse を実行してから、この画面の USB を押します。",
            color = Color(0xFFAABBCC),
            fontSize = 12.sp
        )

        OutlinedTextField(
            value = host,
            onValueChange = { host = it },
            label = { Text("1. SSHホスト / IP") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text("Tailscale: 100.x.x.x / USB: 127.0.0.1") }
        )
        Text(
            "スマホから見える PC のアドレスです。Tailscale なら PC で tailscale ip -4、USB なら 127.0.0.1。",
            color = Color(0xFFAABBCC),
            fontSize = 12.sp
        )

        OutlinedButton(
            onClick = importConnectionProfileFromClipboard,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(4.dp)
        ) {
            Text("接続リンク / JSON を取り込む")
        }
        Text(
            "PC 側で android_pairing_profile.sh を実行すると、接続リンクと JSON が出ます。QR を開ける場合はリンクから自動反映できます。",
            color = Color(0xFFAABBCC),
            fontSize = 12.sp
        )
        SelectionContainer {
            Text(
                "USB用PCコマンド: scripts/android_pairing_profile.sh --mode usb --ssh-port 22 --android-port 2222",
                color = Color(0xFFAABBCC),
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace
            )
        }

        OutlinedTextField(
            value = port,
            onValueChange = { port = it },
            label = { Text("2. SSHポート") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            placeholder = { Text("Tailscale: 22 / USB: 2222") }
        )

        OutlinedTextField(
            value = user,
            onValueChange = { user = it },
            label = { Text("3. SSHユーザー") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text("PC/WSL/Linux/macOS のユーザー名") }
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedTextField(
                value = keyPath,
                onValueChange = {
                    keyPath = it
                    saved = false
                },
                label = { Text("4. SSH秘密鍵パス（任意）") },
                modifier = Modifier.weight(1f),
                singleLine = true,
                placeholder = { Text("/data/data/.../id_ed25519") }
            )
            OutlinedButton(
                onClick = { pickSshKeyLauncher.launch(arrayOf("*/*")) },
                modifier = Modifier.defaultMinSize(minHeight = 56.dp),
                shape = RoundedCornerShape(4.dp)
            ) {
                Text("ファイルを選択")
            }
        }
        Text(
            "分からなければ空欄でOK。パスワードで SSH します。",
            color = Color(0xFFAABBCC),
            fontSize = 12.sp
        )

        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("5. SSHパスワード") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            visualTransformation = PasswordVisualTransformation()
        )

        Divider()

        Text("Shogunate の場所", style = MaterialTheme.typography.titleMedium, color = Kinpaku)

        OutlinedTextField(
            value = projectPath,
            onValueChange = { projectPath = it },
            label = { Text("6. プロジェクトパス（PC側）") },
            placeholder = { Text("/path/to/multi-agent-shognate") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        Text(
            "PC/WSL/Linux/macOS 上の Shogunate フォルダです。接続リンクを使うと自動で入ります。",
            color = Color(0xFFAABBCC),
            fontSize = 12.sp
        )

        Divider()

        Text("セッション設定", style = MaterialTheme.typography.titleMedium, color = Kinpaku)

        OutlinedTextField(
            value = shogunSession,
            onValueChange = { shogunSession = it },
            label = { Text("将軍セッション名") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text("shogun") }
        )

        OutlinedTextField(
            value = agentsSession,
            onValueChange = { agentsSession = it },
            label = { Text("エージェントセッション名") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text("multiagent") }
        )

        Divider()

        NtfySettingsSection(viewModel = settingsViewModel)

        Divider()

        Button(
            onClick = saveSettings,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = Shuaka,
                contentColor = Color.White
            ),
            shape = RoundedCornerShape(4.dp)
        ) {
            Text("保存")
        }

        if (saved) {
            Text(
                text = "設定を保存しました",
                color = MaterialTheme.colorScheme.primary
            )
        }

        Divider()

        HostUpdateSection(
            updateLoading = updateLoading,
            updateResult = updateResult,
            onStatus = {
                saveSettings()
                settingsViewModel.checkHostUpdateStatus()
            },
            onPreview = {
                saveSettings()
                settingsViewModel.previewUpstreamSync()
            },
            onReleaseUpdate = {
                saveSettings()
                settingsViewModel.stopAndApplyReleaseUpdate()
            },
            onUpstreamUpdate = {
                saveSettings()
                settingsViewModel.stopAndApplyUpstreamUpdate()
            }
        )
    }
}

@Composable
private fun HostUpdateSection(
    updateLoading: Boolean,
    updateResult: String,
    onStatus: () -> Unit,
    onPreview: () -> Unit,
    onReleaseUpdate: () -> Unit,
    onUpstreamUpdate: () -> Unit
) {
    Text("本体更新", style = MaterialTheme.typography.titleMedium, color = Kinpaku)
    Text(
        "APK 自体ではなく、SSH 先の Shogunate 本体を更新します。live 更新はせず、停止してから適用します。",
        color = Color(0xFFAABBCC),
        fontSize = 12.sp
    )

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        OutlinedButton(onClick = onStatus, modifier = Modifier.weight(1f), enabled = !updateLoading) {
            Text("状態確認")
        }
        OutlinedButton(onClick = onPreview, modifier = Modifier.weight(1f), enabled = !updateLoading) {
            Text("差分確認")
        }
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Button(
            onClick = onReleaseUpdate,
            modifier = Modifier.weight(1f),
            enabled = !updateLoading,
            colors = ButtonDefaults.buttonColors(containerColor = Shuaka, contentColor = Color.White)
        ) {
            Text("停止してRelease更新")
        }
        Button(
            onClick = onUpstreamUpdate,
            modifier = Modifier.weight(1f),
            enabled = !updateLoading,
            colors = ButtonDefaults.buttonColors(containerColor = Tetsukon, contentColor = Color.White)
        ) {
            Text("停止してUpstream取込")
        }
    }

    if (updateLoading) {
        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
    }

    if (updateResult.isNotBlank()) {
        OutlinedTextField(
            value = updateResult,
            onValueChange = {},
            label = { Text("更新ログ") },
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 120.dp),
            readOnly = true
        )
    }
}

private fun copySshKeyToAppStorage(context: Context, uri: Uri): String {
    val resolver = context.contentResolver
    val displayName = resolver.query(
        uri,
        arrayOf(OpenableColumns.DISPLAY_NAME),
        null,
        null,
        null
    )?.use { cursor ->
        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
    }
    val sanitizedName = (displayName ?: "ssh_key.pem").replace(Regex("[^A-Za-z0-9._-]"), "_")
    val keyDir = File(context.filesDir, "ssh_keys")
    if (!keyDir.exists() && !keyDir.mkdirs()) {
        error("鍵保存先を作成できませぬ")
    }
    val targetFile = File(keyDir, "${System.currentTimeMillis()}_$sanitizedName")

    resolver.openInputStream(uri)?.use { input ->
        targetFile.outputStream().use { output ->
            input.copyTo(output)
        }
    } ?: error("鍵ファイルを開けませぬ")

    return targetFile.absolutePath
}

@Composable
fun DebugLogDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val entries = remember { AppLogger.getEntries() }
    val listState = rememberLazyListState()

    LaunchedEffect(entries.size) {
        if (entries.isNotEmpty()) listState.scrollToItem(entries.size - 1)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Shikkoku,
        title = {
            Text("Debug Log (${entries.size})", color = Kinpaku)
        },
        text = {
            Column {
                // Copy to clipboard button
                TextButton(onClick = {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = ClipData.newPlainText("debug_log", entries.joinToString("\n"))
                    clipboard.setPrimaryClip(clip)
                    Toast.makeText(context, "ログをコピーしました", Toast.LENGTH_SHORT).show()
                }) {
                    Text("Copy All", color = Kinpaku)
                }
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(380.dp)
                ) {
                    items(entries) { entry ->
                        Text(
                            text = entry,
                            color = if (entry.contains("FAIL") || entry.contains("ERROR"))
                                Color(0xFFCC3333) else Color(0xFFAABBCC),
                            fontFamily = FontFamily.Monospace,
                            fontSize = 10.sp,
                            modifier = Modifier.padding(vertical = 1.dp)
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                AppLogger.clear()
                onDismiss()
            }) {
                Text("Clear & Close", color = Kinpaku)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Close", color = Color(0xFF888888))
            }
        }
    )
}
