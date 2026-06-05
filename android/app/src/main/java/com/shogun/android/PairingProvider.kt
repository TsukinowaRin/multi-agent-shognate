package com.shogun.android

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import com.shogun.android.util.AndroidSshKeyManager

class PairingProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        if (uri.path != "/profile") return null
        val context = context ?: return null
        val profile = AndroidSshKeyManager.ensurePairingProfile(context)
        return MatrixCursor(arrayOf("public_key", "key_path", "device_label")).apply {
            addRow(arrayOf(profile.publicKey, profile.keyPath, profile.deviceLabel))
        }
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
