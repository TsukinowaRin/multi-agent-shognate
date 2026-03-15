package com.shogun.android.ssh

import android.content.Context
import android.net.Uri
import com.jcraft.jsch.ChannelExec
import com.jcraft.jsch.ChannelSftp
import com.jcraft.jsch.JSch
import com.jcraft.jsch.Session
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import com.shogun.android.util.AppLogger
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Properties

class SshManager private constructor() {

    companion object {
        @Volatile private var INSTANCE: SshManager? = null
        fun getInstance(): SshManager = INSTANCE ?: synchronized(this) {
            INSTANCE ?: SshManager().also { INSTANCE = it }
        }
    }

    @Volatile private var session: Session? = null

    // Mutex serializes ALL SSH operations (exec, reconnect, connect).
    // Prevents race condition where multiple ViewModels' concurrent reconnects
    // kill each other's newly-created sessions.
    private val sshMutex = Mutex()

    // Stored for reconnect
    private var lastHost = ""
    private var lastPort = 22
    private var lastUser = ""
    private var lastKeyPath = ""
    private var lastPassword = ""

    var disconnectCallback: (() -> Unit)? = null

    suspend fun connect(
        host: String,
        port: Int,
        user: String,
        privateKeyPath: String,
        password: String = "",
        onOutput: ((String) -> Unit)? = null,
        onDisconnect: (() -> Unit)? = null
    ): Result<Unit> = withContext(Dispatchers.IO) {
        if (onDisconnect != null) disconnectCallback = onDisconnect

        sshMutex.withLock {
            if (isConnectedInternal()) {
                AppLogger.log("SSH", "Already connected, skipping")
                return@withContext Result.success(Unit)
            }

            AppLogger.log("SSH", "Connecting to $host:$port user=$user key=${privateKeyPath.takeLast(20)}")
            lastHost = host
            lastPort = port
            lastUser = user
            lastKeyPath = privateKeyPath
            lastPassword = password
            connectInternal()
        }
    }

    private fun connectInternal(): Result<Unit> {
        val trimmedKeyPath = lastKeyPath.trim()
        val primaryMode = if (trimmedKeyPath.isNotBlank()) "publickey" else "password"
        val primary = connectInternalOnce(usePublicKey = trimmedKeyPath.isNotBlank())
        if (primary.isSuccess) return Result.success(Unit)

        val primaryError = primary.exceptionOrNull()
        val canRetryWithPassword = trimmedKeyPath.isNotBlank() && lastPassword.trim().isNotEmpty()
        if (!canRetryWithPassword) {
            AppLogger.log("SSH", "Connect FAILED (mode=$primaryMode): ${primaryError?.message}")
            return Result.failure(Exception("SSH接続失敗 (${primaryMode}, pw=${lastPassword.trim().length}文字): ${primaryError?.message}", primaryError))
        }

        AppLogger.log("SSH", "Publickey auth failed, retrying with password auth")
        val fallback = connectInternalOnce(usePublicKey = false)
        if (fallback.isSuccess) {
            AppLogger.log("SSH", "Password fallback succeeded after publickey failure")
            return Result.success(Unit)
        }

        val fallbackError = fallback.exceptionOrNull()
        AppLogger.log("SSH", "Connect FAILED after fallback: ${fallbackError?.message}")
        return Result.failure(
            Exception(
                "SSH接続失敗 (鍵→パスワード再試行済み, pw=${lastPassword.trim().length}文字): ${fallbackError?.message}",
                fallbackError
            )
        )
    }

    private fun connectInternalOnce(usePublicKey: Boolean): Result<Unit> {
        return try {
            val trimmedPassword = lastPassword.trim()
            val trimmedKeyPath = lastKeyPath.trim()
            val jsch = JSch()
            if (usePublicKey && trimmedKeyPath.isNotBlank()) {
                jsch.addIdentity(trimmedKeyPath)
            }
            val newSession = jsch.getSession(lastUser, lastHost, lastPort)
            val config = Properties()
            config["StrictHostKeyChecking"] = "no"
            config["MaxAuthTries"] = "2"
            config["PreferredAuthentications"] = if (usePublicKey) {
                "publickey"
            } else {
                "keyboard-interactive,password"
            }
            newSession.setConfig(config)
            if (!usePublicKey && trimmedPassword.isNotEmpty()) {
                newSession.setPassword(trimmedPassword)
            }
            var passwordAttempted = false
            val userInfo = object : com.jcraft.jsch.UserInfo {
                override fun getPassword(): String = trimmedPassword
                override fun promptPassword(message: String): Boolean {
                    if (passwordAttempted) return false
                    passwordAttempted = true
                    return true
                }
                override fun promptPassphrase(message: String): Boolean = true
                override fun getPassphrase(): String = ""
                override fun promptYesNo(message: String): Boolean = true
                override fun showMessage(message: String) {}
            }
            newSession.userInfo = userInfo
            newSession.connect(10000)
            session = newSession
            val testResult = execCommandInternal(newSession, "echo ssh_exec_ok")
            if (testResult.isSuccess) {
                val out = testResult.getOrDefault("").trim()
                AppLogger.log("SSH", "Connected OK (mode=${if (usePublicKey) "publickey" else "password"}, exec verified: $out)")
            } else {
                AppLogger.log("SSH", "Connected but exec FAILED: ${testResult.exceptionOrNull()?.message}")
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    fun isConnected(): Boolean = session?.isConnected == true
    private fun isConnectedInternal(): Boolean = session?.isConnected == true

    /**
     * Execute a remote command via SSH exec channel.
     * All operations are serialized by sshMutex to prevent concurrent reconnect storms.
     * On session failure, reconnects and retries once.
     */
    suspend fun execCommand(cmd: String): Result<String> = withContext(Dispatchers.IO) {
        sshMutex.withLock {
            val s = session
            if (s == null || !s.isConnected) {
                AppLogger.log("SSH", "exec: session dead, reconnecting...")
                val reconn = reconnectLocked()
                if (reconn.isFailure) {
                    disconnectCallback?.invoke()
                    return@withContext Result.failure(IllegalStateException("SSH not connected"))
                }
            }

            val currentSession = session
            if (currentSession == null) {
                return@withContext Result.failure(IllegalStateException("SSH not connected"))
            }

            val result = execCommandInternal(currentSession, cmd)
            if (result.isSuccess) {
                return@withContext result
            }

            // Session died mid-exec — reconnect and retry once
            val errorMsg = result.exceptionOrNull()?.message ?: ""
            if (errorMsg.contains("channel is not opened") || errorMsg.contains("session is down")) {
                AppLogger.log("SSH", "exec failed (session dead), auto-reconnecting...")
                val reconn = reconnectLocked()
                if (reconn.isSuccess) {
                    val retrySession = session
                    if (retrySession != null) {
                        AppLogger.log("SSH", "Retrying exec after reconnect...")
                        return@withContext execCommandInternal(retrySession, cmd)
                    }
                }
                disconnectCallback?.invoke()
            }

            result
        }
    }

    /**
     * Reconnect while sshMutex is already held.
     * No synchronization needed — caller holds the mutex.
     */
    private fun reconnectLocked(): Result<Unit> {
        AppLogger.log("SSH", "reconnectLocked: disconnecting old session...")
        session?.disconnect()
        session = null
        val result = connectInternal()
        if (result.isSuccess) {
            AppLogger.log("SSH", "reconnectLocked: success")
        } else {
            AppLogger.log("SSH", "reconnectLocked: failed: ${result.exceptionOrNull()?.message}")
        }
        return result
    }

    private fun execCommandInternal(s: Session, cmd: String): Result<String> {
        val shortCmd = if (cmd.length > 80) cmd.take(80) + "..." else cmd
        return try {
            val channel = s.openChannel("exec") as ChannelExec
            channel.setCommand(cmd)
            val inputStream = channel.inputStream
            channel.connect(5000)
            val baos = ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            while (true) {
                val n = inputStream.read(buffer)
                if (n < 0) break
                baos.write(buffer, 0, n)
            }
            channel.disconnect()
            val out = baos.toString("UTF-8")
            AppLogger.log("SSH", "exec OK (${out.length}ch): $shortCmd")
            Result.success(out)
        } catch (e: Exception) {
            val trace = e.stackTraceToString().take(500)
            AppLogger.log("SSH", "exec FAIL: ${e.message} cmd=$shortCmd")
            AppLogger.log("SSH", "exec TRACE: $trace")
            Result.failure(e)
        }
    }

    suspend fun reconnect(maxAttempts: Int = 3, delayMs: Long = 5000): Result<Unit> =
        withContext(Dispatchers.IO) {
            AppLogger.log("SSH", "reconnect start (max=$maxAttempts)")
            var lastError: Exception? = null
            for (attempt in 0 until maxAttempts) {
                sshMutex.withLock {
                    session?.disconnect()
                    session = null
                    val result = connectInternal()
                    if (result.isSuccess) return@withContext Result.success(Unit)
                    lastError = result.exceptionOrNull() as? Exception
                    AppLogger.log("SSH", "reconnect attempt ${attempt + 1} failed: ${lastError?.message}")
                }
                if (attempt < maxAttempts - 1) Thread.sleep(delayMs)
            }
            Result.failure(lastError ?: Exception("再接続失敗（${maxAttempts}回試行）"))
        }

    suspend fun uploadScreenshot(context: Context, imageUri: Uri, projectPath: String = ""): Result<String> =
        withContext(Dispatchers.IO) {
            sshMutex.withLock {
            val s = session
            if (s == null || !s.isConnected) {
                return@withContext Result.failure(IllegalStateException("SSH not connected"))
            }
            try {
                val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
                val fileName = "screenshot_$timestamp.png"
                val remoteDir = "$projectPath/queue/screenshots"
                val remotePath = "$remoteDir/$fileName"

                val channelSftp = s.openChannel("sftp") as ChannelSftp
                channelSftp.connect(5000)
                try {
                    try { channelSftp.mkdir(remoteDir) } catch (_: Exception) { /* already exists */ }
                    context.contentResolver.openInputStream(imageUri)?.use { inputStream ->
                        channelSftp.put(inputStream, remotePath)
                    } ?: return@withContext Result.failure(Exception("Cannot open image URI"))
                    Result.success(fileName)
                } finally {
                    channelSftp.disconnect()
                }
            } catch (e: Exception) {
                Result.failure(e)
            }
            } // sshMutex.withLock
        }

    fun disconnect() {
        AppLogger.log("SSH", "disconnect() called")
        session?.disconnect()
        session = null
    }
}
