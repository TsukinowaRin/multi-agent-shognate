package com.shogun.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shogun.android.ui.theme.BorderFocus
import com.shogun.android.ui.theme.BorderStandard
import com.shogun.android.ui.theme.Kinpaku
import com.shogun.android.ui.theme.Kurenai
import com.shogun.android.ui.theme.Surface4
import com.shogun.android.ui.theme.TextMuted
import com.shogun.android.ui.theme.Zouge

@Composable
internal fun ShogunInputArea(
    inputTextValue: TextFieldValue,
    onInputChange: (TextFieldValue) -> Unit,
    isInputExpanded: Boolean,
    onToggleInputExpanded: () -> Unit,
    isConnected: Boolean,
    isListening: Boolean,
    shogunPaneBusy: Boolean,
    canSend: Boolean,
    isBgmPlaying: Boolean,
    bgmTrackLabel: String,
    onBgmToggle: () -> Unit,
    onSend: () -> Unit,
    onVoiceToggle: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(
                onClick = onToggleInputExpanded,
                modifier = Modifier.size(40.dp)
            ) {
                Icon(
                    imageVector = if (isInputExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                    contentDescription = "入力欄を展開",
                    tint = Kinpaku
                )
            }
            OutlinedTextField(
                value = inputTextValue,
                onValueChange = onInputChange,
                modifier = Modifier.weight(1f),
                placeholder = {
                    Text(
                        text = if (shogunPaneBusy) "将軍が処理中です" else "コマンドを入力",
                        color = TextMuted,
                        maxLines = 1,
                        softWrap = false
                    )
                },
                singleLine = !isInputExpanded,
                maxLines = if (isInputExpanded) 6 else 1,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Zouge,
                    unfocusedTextColor = Zouge,
                    focusedBorderColor = BorderFocus,
                    unfocusedBorderColor = BorderStandard,
                    cursorColor = Kinpaku,
                    focusedContainerColor = Surface4,
                    unfocusedContainerColor = Surface4,
                )
            )
            IconButton(
                onClick = onSend,
                enabled = canSend,
                modifier = Modifier.size(44.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Send,
                    contentDescription = "送信",
                    tint = if (canSend) Kinpaku else TextMuted
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedButton(
                onClick = onBgmToggle,
                modifier = Modifier.height(40.dp),
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                border = BorderStroke(1.dp, if (isBgmPlaying) BorderFocus else BorderStandard),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = Surface4,
                    contentColor = if (isBgmPlaying) Kinpaku else TextMuted
                )
            ) {
                Icon(
                    imageVector = if (isBgmPlaying) Icons.Default.VolumeUp else Icons.Default.VolumeOff,
                    contentDescription = "BGM",
                    tint = if (isBgmPlaying) Kinpaku else TextMuted,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = if (isBgmPlaying && bgmTrackLabel.isNotEmpty()) bgmTrackLabel else "BGM",
                    fontSize = 12.sp,
                    maxLines = 1
                )
            }
            IconButton(
                onClick = onVoiceToggle,
                enabled = isConnected
            ) {
                Icon(
                    imageVector = Icons.Default.Mic,
                    contentDescription = "音声入力",
                    tint = if (isListening) Kurenai else Kinpaku
                )
            }
        }
    }
}
