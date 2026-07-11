package com.shogun.android.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.shogun.android.ui.theme.*
import com.shogun.android.util.Defaults
import com.shogun.android.util.PrefsKeys
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shogun.android.R
import com.shogun.android.viewmodel.ShogunViewModel

private enum class ShogunDisplayMode {
    Chat,
    RawLog
}

private data class ShogunChatMessage(
    val fromUser: Boolean,
    val text: String
)

@Composable
fun ShogunScreen(
    viewModel: ShogunViewModel = viewModel(),
    mediaPlayer: MediaPlayer? = null,
    isBgmPlaying: Boolean = false,
    bgmTrackLabel: String = "",
    onBgmToggle: () -> Unit = {}
) {
    val context = LocalContext.current
    val paneContent by viewModel.paneContent.collectAsState()
    val isConnected by viewModel.isConnected.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val draftText by viewModel.draftText.collectAsState()
    val targetMissing = errorMessage?.contains("pane が見つかりません") == true
    val shogunPaneBusy = remember(paneContent) { isShogunPaneBusy(paneContent) }
    val shogunComposerDirty = remember(paneContent) { isShogunComposerDirty(paneContent) }

    var inputTextValue by remember { mutableStateOf(TextFieldValue(draftText, selection = TextRange(draftText.length))) }
    var isListening by remember { mutableStateOf(false) }
    var isInputExpanded by remember { mutableStateOf(false) }
    var displayMode by remember { mutableStateOf(ShogunDisplayMode.Chat) }
    val canSend = inputTextValue.text.isNotBlank() && isConnected && !isListening && !shogunPaneBusy

    LaunchedEffect(draftText) {
        if (draftText != inputTextValue.text) {
            inputTextValue = TextFieldValue(draftText, selection = TextRange(draftText.length))
        }
    }

    // Duck BGM while voice input is active
    LaunchedEffect(isListening) {
        if (isListening) {
            mediaPlayer?.setVolume(0.05f, 0.05f)
        } else {
            mediaPlayer?.setVolume(1.0f, 1.0f)
        }
    }

    val listState = rememberLazyListState()
    val lines = remember(paneContent) { paneContent.lines() }
    val chatMessages = remember(paneContent) { parseShogunChatMessages(paneContent) }

    val speechRecognizer = remember {
        if (SpeechRecognizer.isRecognitionAvailable(context))
            SpeechRecognizer.createSpeechRecognizer(context)
        else null
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted && speechRecognizer != null) {
            startContinuousListening(speechRecognizer, { isListening }) { result ->
                val newText = if (inputTextValue.text.isEmpty()) result else "${inputTextValue.text} $result"
                inputTextValue = TextFieldValue(text = newText, selection = TextRange(newText.length))
                viewModel.setDraftText(newText)
            }
            isListening = true
        }
    }

    // Auto-connect on composition
    LaunchedEffect(Unit) {
        val prefs = context.getSharedPreferences(PrefsKeys.PREFS_NAME, android.content.Context.MODE_PRIVATE)
        val host = prefs.getString(PrefsKeys.SSH_HOST, Defaults.SSH_HOST) ?: Defaults.SSH_HOST
        val port = prefs.getString(PrefsKeys.SSH_PORT, Defaults.SSH_PORT_STR)?.toIntOrNull() ?: Defaults.SSH_PORT
        val user = prefs.getString(PrefsKeys.SSH_USER, "") ?: ""
        val keyPath = prefs.getString(PrefsKeys.SSH_KEY_PATH, "") ?: ""
        val password = prefs.getString(PrefsKeys.SSH_PASSWORD, "") ?: ""
        viewModel.connect(host, port, user, keyPath, password)
    }

    // Pause refresh when app is in background
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    viewModel.resumeRefresh()
                    if (isListening && speechRecognizer != null) {
                        startContinuousListening(speechRecognizer, { isListening }) { result ->
                            val newText = if (inputTextValue.text.isEmpty()) result else "${inputTextValue.text} $result"
                            inputTextValue = TextFieldValue(text = newText, selection = TextRange(newText.length))
                            viewModel.setDraftText(newText)
                        }
                    }
                }
                Lifecycle.Event.ON_PAUSE -> {
                    viewModel.pauseRefresh()
                    speechRecognizer?.cancel()
                }
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // Auto-scroll to bottom when content changes
    LaunchedEffect(lines.size, chatMessages.size, displayMode) {
        val itemCount = if (displayMode == ShogunDisplayMode.Chat) chatMessages.size else lines.size
        if (itemCount > 0) {
            listState.scrollToItem(itemCount - 1)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Shikkoku)
    ) {
        Image(
            painter = painterResource(R.drawable.bg_shogun),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            alpha = 0.55f,
            modifier = Modifier.fillMaxSize()
        )
        Column(modifier = Modifier.fillMaxSize()) {
        // 陣幕バー — connection status
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    when {
                        isConnected && targetMissing -> Kinpaku
                        isConnected -> Matsuba
                        else -> Kurenai
                    }
                )
                .padding(4.dp),
            horizontalArrangement = Arrangement.Center
        ) {
            Text(
                text = when {
                    isConnected && targetMissing -> "SSH接続中 — pane未検出"
                    isConnected && shogunPaneBusy -> "処理中 — 将軍セッション"
                    isConnected && shogunComposerDirty -> "入力待ち — 将軍側の下書きあり"
                    isConnected -> "接続中 — 将軍セッション"
                    else -> "未接続"
                },
                color = if (targetMissing) Shikkoku else Zouge,
                fontSize = 12.sp
            )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0x802D2D2D))
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.End
        ) {
            FilterChip(
                selected = displayMode == ShogunDisplayMode.Chat,
                onClick = { displayMode = ShogunDisplayMode.Chat },
                label = { Text("会話") },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = Surface4,
                    selectedLabelColor = Kinpaku,
                    labelColor = Zouge
                )
            )
            Spacer(modifier = Modifier.width(6.dp))
            FilterChip(
                selected = displayMode == ShogunDisplayMode.RawLog,
                onClick = { displayMode = ShogunDisplayMode.RawLog },
                label = { Text("RAWログ") },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = Surface4,
                    selectedLabelColor = Kinpaku,
                    labelColor = Zouge
                )
            )
        }

        // Pane content display with LazyColumn
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
        ) {
            if (errorMessage != null) {
                Text(
                    text = "エラー: $errorMessage",
                    color = Kurenai,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 13.sp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp)
                )
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                ) {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxHeight()
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        if (displayMode == ShogunDisplayMode.Chat) {
                            if (chatMessages.isEmpty()) {
                                item {
                                    Text(
                                        text = "会話として表示できるメッセージはまだありません",
                                        color = TextMuted,
                                        fontSize = 13.sp,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(12.dp)
                                    )
                                }
                            } else {
                                items(chatMessages) { message ->
                                    ShogunMessageBubble(message)
                                }
                            }
                        } else {
                            items(lines) { line ->
                                SelectionContainer {
                                    Text(
                                        text = parseAnsiColors(line),
                                        color = Zouge,
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 13.sp,
                                        softWrap = true,
                                        modifier = Modifier.fillMaxWidth()
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // Special keys bar
        SpecialKeysRow(onSendKey = { viewModel.sendRawKey(it) })

        ShogunInputArea(
            inputTextValue = inputTextValue,
            onInputChange = {
                inputTextValue = it
                viewModel.setDraftText(it.text)
            },
            isInputExpanded = isInputExpanded,
            onToggleInputExpanded = { isInputExpanded = !isInputExpanded },
            isConnected = isConnected,
            isListening = isListening,
            shogunPaneBusy = shogunPaneBusy,
            canSend = canSend,
            isBgmPlaying = isBgmPlaying,
            bgmTrackLabel = bgmTrackLabel,
            onBgmToggle = onBgmToggle,
            onSend = {
                viewModel.sendCommand(inputTextValue.text)
                inputTextValue = TextFieldValue("")
                viewModel.clearDraftText()
            },
            onVoiceToggle = {
                if (speechRecognizer != null) {
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                        == PackageManager.PERMISSION_GRANTED
                    ) {
                        if (isListening) {
                            speechRecognizer.cancel()
                            isListening = false
                        } else {
                            startContinuousListening(speechRecognizer, { isListening }) { result ->
                                val newText = if (inputTextValue.text.isEmpty()) result else "${inputTextValue.text} $result"
                                inputTextValue = TextFieldValue(text = newText, selection = TextRange(newText.length))
                                viewModel.setDraftText(newText)
                            }
                            isListening = true
                        }
                    } else {
                        permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                    }
                }
            }
        )
        } // Column (main)
    } // Box
}

@Composable
fun SpecialKeysRow(onSendKey: (String) -> Unit) {
    // Ordered by usage frequency for tmux + Claude Code workflow
    val specialKeys = listOf(
        "↵" to "\n",        // Enter — most used (confirm commands, send input)
        "C-c" to "\u0003",  // Interrupt — stop running process
        "C-b" to "\u0002",  // tmux prefix — pane control (C-b C-b for background)
        "↑" to "\u001b[A",  // History up
        "↓" to "\u001b[B",  // History down
        "Tab" to "\t",      // Autocomplete
        "ESC" to "\u001b",  // Cancel / exit mode
        "C-o" to "\u000f",  // Accept line in Claude Code
        "C-d" to "\u0004"   // EOF / exit
    )
    LazyRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        items(specialKeys) { (label, value) ->
            OutlinedButton(
                onClick = { onSendKey(value) },
                modifier = Modifier.height(32.dp),
                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
                border = BorderStroke(1.dp, BorderFocus),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = Surface4,
                    contentColor = Zouge
                )
            ) {
                Text(
                    text = label,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
    }
}

@Composable
private fun ShogunMessageBubble(message: ShogunChatMessage) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = if (message.fromUser) Arrangement.End else Arrangement.Start
    ) {
        Surface(
            color = if (message.fromUser) Surface4 else Color(0xCC151515),
            tonalElevation = 1.dp,
            shape = MaterialTheme.shapes.small,
            border = BorderStroke(1.dp, if (message.fromUser) BorderFocus else Color(0x665C5640)),
            modifier = Modifier.widthIn(max = 320.dp)
        ) {
            Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                Text(
                    text = if (message.fromUser) "あなた" else "将軍",
                    color = if (message.fromUser) Kinpaku else Zouge,
                    fontSize = 11.sp
                )
                Spacer(modifier = Modifier.height(4.dp))
                SelectionContainer {
                    Text(
                        text = message.text,
                        color = Zouge,
                        fontSize = 14.sp,
                        lineHeight = 20.sp
                    )
                }
            }
        }
    }
}

private fun parseShogunChatMessages(raw: String): List<ShogunChatMessage> {
    val messages = mutableListOf<ShogunChatMessage>()
    val current = StringBuilder()
    var currentFromUser: Boolean? = null
    var currentUserSubmitted = false
    var skippingUserPrompt = false
    var seenBusyStatus = false

    fun flush() {
        val text = current.toString().trim()
        val fromUser = currentFromUser
        if (fromUser != null && text.isNotBlank() && (!fromUser || currentUserSubmitted)) {
            messages.add(ShogunChatMessage(fromUser, text))
        }
        current.clear()
        currentFromUser = null
        currentUserSubmitted = false
    }

    fun start(fromUser: Boolean, text: String) {
        flush()
        currentFromUser = fromUser
        currentUserSubmitted = !fromUser
        current.append(text.trim())
    }

    for (sourceLine in raw.lines()) {
        val line = stripTerminalControl(sourceLine).trimEnd()
        val trimmed = line.trim()
        if (trimmed.isBlank()) {
            if (skippingUserPrompt) skippingUserPrompt = false
            continue
        }
        if (isCodexBusyLine(trimmed)) {
            if (currentFromUser == true) {
                currentUserSubmitted = true
            }
            seenBusyStatus = true
            continue
        }
        if (isTerminalNoiseLine(trimmed)) continue

        if (trimmed.startsWith("› ")) {
            val prompt = trimmed.removePrefix("› ").trim()
            if (seenBusyStatus) {
                // Codex shows editable composer text below the active Working block.
                // That text is not a completed user turn yet.
                continue
            } else if (isIgnoredPrompt(prompt)) {
                skippingUserPrompt = true
                flush()
            } else {
                skippingUserPrompt = false
                start(fromUser = true, text = prompt)
            }
            continue
        }
        if (skippingUserPrompt) continue

        if (trimmed.startsWith("• ")) {
            if (currentFromUser == true) {
                currentUserSubmitted = true
            }
            seenBusyStatus = false
            val message = trimmed.removePrefix("• ").trim()
            if (!isCodexStatusLine(message)) {
                start(fromUser = false, text = message)
            }
            continue
        }

        if (currentFromUser != null && shouldAppendToCurrent(trimmed)) {
            if (current.isNotEmpty()) current.append('\n')
            current.append(trimmed)
        }
    }
    flush()
    return messages.takeLast(30)
}

private fun stripTerminalControl(text: String): String =
    text
        .replace(Regex("\\u001B\\[[0-9;?]*[ -/]*[@-~]"), "")
        .replace(Regex("[⠁-⣿]"), "")

private fun isTerminalNoiseLine(line: String): Boolean {
    if (line.all { it in "─━═ │┃┌┐└┘╭╮╰╯┏┓┗┛╔╗╚╝╠╣╦╩╬+-_ " }) return true
    return line.startsWith("╭") ||
        line.startsWith("╰") ||
        line.startsWith("│") ||
        line.startsWith("└") ||
        line.startsWith("┌") ||
        line.startsWith("Tip:") ||
        line.startsWith("Learn more:") ||
        line.startsWith("model:") ||
        line.startsWith("directory:") ||
        line.startsWith("permissions:") ||
        line.startsWith("gpt-") ||
        line.startsWith("Backed up Codex local data") ||
        line.startsWith("Retrying startup") ||
        line.startsWith("Codex couldn't start") ||
        line.startsWith("Repair Codex local data") ||
        line.startsWith("Technical details:") ||
        line.startsWith("Location:") ||
        line.startsWith("Cause:") ||
        line.startsWith("returned from database:")
}

private fun isShogunPaneBusy(raw: String): Boolean =
    raw.lines()
        .map { stripTerminalControl(it).trim() }
        .any { isCodexBusyLine(it) }

private fun isShogunComposerDirty(raw: String): Boolean {
    var dirty = false
    for (sourceLine in raw.lines()) {
        val trimmed = stripTerminalControl(sourceLine).trim()
        if (trimmed.isBlank() || isTerminalNoiseLine(trimmed)) continue
        if (isCodexBusyLine(trimmed) || trimmed.startsWith("• ")) {
            dirty = false
            continue
        }
        if (trimmed.startsWith("› ")) {
            val prompt = trimmed.removePrefix("› ").trim()
            dirty = prompt.isNotBlank() && !isIgnoredPrompt(prompt)
        }
    }
    return dirty
}

private fun isCodexBusyLine(line: String): Boolean =
    line.startsWith("◦ Working") ||
        line.contains("esc to interrupt")

private fun isIgnoredPrompt(prompt: String): Boolean =
    prompt.startsWith("【初動命令】") ||
        prompt == "Write tests for @filename" ||
        prompt == "Find and fix a bug in @filename" ||
        prompt == "Summarize recent commits"

private fun isCodexStatusLine(text: String): Boolean =
    text.startsWith("Ran ") ||
        text.startsWith("Explored") ||
        text.startsWith("Working") ||
        text.contains("bootstrap_") ||
        text.contains("初動") ||
        text.startsWith("Messages to be submitted") ||
        text.startsWith("Booting MCP") ||
        text.startsWith("Called ") ||
        text.startsWith("Updated ") ||
        Regex("^ready:[a-z0-9_-]+$").matches(text)

private fun shouldAppendToCurrent(line: String): Boolean =
    !isTerminalNoiseLine(line) &&
        !line.startsWith("› ") &&
        !line.startsWith("• ") &&
        !line.startsWith("◦ ") &&
        !line.startsWith("─ Worked for")

/**
 * Continuous listening — auto-restarts after each result.
 * Checks isActive() before restarting to respect user's OFF toggle.
 * Caller should use cancel() (not stopListening()) to stop cleanly.
 */
fun startContinuousListening(
    speechRecognizer: SpeechRecognizer,
    isActive: () -> Boolean,
    onResult: (String) -> Unit
) {
    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ja-JP")
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 5000L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 5000L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 2000L)
    }
    speechRecognizer.setRecognitionListener(object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onError(error: Int) {
            if (!isActive()) return
            when (error) {
                SpeechRecognizer.ERROR_AUDIO,
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                    // Fatal — do not restart
                }
                else -> {
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        if (isActive()) {
                            try { speechRecognizer.startListening(intent) } catch (_: Exception) {}
                        }
                    }, 300)
                }
            }
        }
        override fun onResults(results: Bundle?) {
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            if (!matches.isNullOrEmpty()) {
                onResult(matches[0])
            }
            if (isActive()) {
                speechRecognizer.startListening(intent)
            }
        }
        override fun onPartialResults(partialResults: Bundle?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    })
    speechRecognizer.startListening(intent)
}
