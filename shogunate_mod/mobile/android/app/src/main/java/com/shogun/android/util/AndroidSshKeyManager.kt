package com.shogun.android.util

import android.content.Context
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.interfaces.RSAPublicKey
import java.util.Base64

data class AndroidSshPairingProfile(
    val publicKey: String,
    val keyPath: String,
    val deviceLabel: String
)

object AndroidSshKeyManager {
    private const val KEY_FILE_NAME = "shogunate_mobile_rsa.pem"

    fun ensurePairingProfile(context: Context): AndroidSshPairingProfile {
        val keyDir = context.filesDir.resolve("ssh_keys")
        if (!keyDir.exists() && !keyDir.mkdirs()) {
            error("SSH鍵保存先を作成できません")
        }

        val keyFile = keyDir.resolve(KEY_FILE_NAME)
        val publicFile = keyDir.resolve("$KEY_FILE_NAME.pub")
        val deviceLabel = listOf(Build.MANUFACTURER, Build.MODEL)
            .joinToString("-")
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .ifBlank { "android" }

        if (!keyFile.isFile || !publicFile.isFile) {
            val keyPair = KeyPairGenerator.getInstance("RSA").apply {
                initialize(4096)
            }.generateKeyPair()
            val privatePem = pem("PRIVATE KEY", keyPair.private.encoded)
            val publicKey = authorizedKey(keyPair.public as RSAPublicKey, "shogunate-android-$deviceLabel")

            keyFile.writeText(privatePem)
            publicFile.writeText(publicKey)
            keyFile.setReadable(false, false)
            keyFile.setWritable(false, false)
            keyFile.setReadable(true, true)
            keyFile.setWritable(true, true)
        }

        return AndroidSshPairingProfile(
            publicKey = publicFile.readText().trim(),
            keyPath = keyFile.absolutePath,
            deviceLabel = deviceLabel
        )
    }

    private fun pem(type: String, der: ByteArray): String {
        val body = Base64.getMimeEncoder(64, "\n".toByteArray()).encodeToString(der)
        return "-----BEGIN $type-----\n$body\n-----END $type-----\n"
    }

    private fun authorizedKey(publicKey: RSAPublicKey, comment: String): String {
        val blob = ByteArrayOutputStream().use { bytes ->
            DataOutputStream(bytes).use { out ->
                out.writeSshString("ssh-rsa".toByteArray(Charsets.US_ASCII))
                out.writeMpInt(publicKey.publicExponent)
                out.writeMpInt(publicKey.modulus)
            }
            bytes.toByteArray()
        }
        return "ssh-rsa ${Base64.getEncoder().encodeToString(blob)} $comment"
    }

    private fun DataOutputStream.writeSshString(value: ByteArray) {
        writeInt(value.size)
        write(value)
    }

    private fun DataOutputStream.writeMpInt(value: BigInteger) {
        val bytes = value.toByteArray()
        writeInt(bytes.size)
        write(bytes)
    }
}
