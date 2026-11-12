package com.example.system_wallpaper

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Failure carrying a stable code the Dart side maps to user-facing copy. */
class DownloadFailure(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/**
 * Writes downloaded wallpapers to the two supported destinations.
 *
 * * default — MediaStore insert under `Pictures/<folderName>`. The app owns the
 *   inserted row, so this needs no storage permission and the result is
 *   indexed by the gallery.
 * * chosen — copy into `<folderName>` inside a tree the user granted through
 *   `ACTION_OPEN_DOCUMENT_TREE`. The grant is persisted (read+write) and
 *   re-validated on every write; a revoked or moved folder fails loudly.
 *
 * Nothing here falls back to the default destination: a chosen folder that
 * stopped working must be reported, not silently replaced.
 */
object DownloadHandler {
    /** MediaStore collection that the gallery indexes. */
    private val mediaCollection: Uri
        get() = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

    /** Writes [source] into `<folderName>`, or the default Pictures folder. */
    suspend fun save(
        context: Context,
        source: File,
        folderName: String,
        mimeType: String,
        treeUri: Uri?,
    ): Uri = withContext(Dispatchers.IO) {
        if (!source.exists()) {
            throw DownloadFailure("notFound", "The downloaded file is missing.")
        }
        if (treeUri == null) {
            saveToMediaStore(context, source, folderName, mimeType)
        } else {
            saveToTree(context, source, treeUri, folderName, mimeType)
        }
    }

    /**
     * Takes the persistable grant for [treeUri], validates it, and returns the
     * folder's provider display name.
     *
     * The new grant is persisted only after read+write access and a resolvable
     * document have both been confirmed.
     */
    suspend fun adoptTree(
        context: Context,
        treeUri: Uri,
        takeFlags: Int,
    ): String = withContext(Dispatchers.IO) {
        if (takeFlags and android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION == 0) {
            throw DownloadFailure(
                "noWriteAccess",
                "That folder can only be read. Choose a folder this app can save into.",
            )
        }
        // A grant may already exist for this tree (re-selecting the folder).
        // That grant can be in use by an in-flight save, so it must survive a
        // validation failure here; only a grant this call acquired is rolled
        // back.
        val hadPersistedAccess = hasPersistedWrite(context, treeUri)
        try {
            context.contentResolver.takePersistableUriPermission(treeUri, takeFlags)
        } catch (e: SecurityException) {
            throw DownloadFailure(
                "noWriteAccess",
                "That folder could not be opened for saving.",
                e,
            )
        }
        val label = try {
            treeLabel(context, treeUri, requireWriteGrant = true)
        } catch (e: Exception) {
            null
        }
        if (label == null) {
            if (!hadPersistedAccess) {
                releaseTree(context, treeUri)
            }
            throw DownloadFailure(
                "noWriteAccess",
                "That folder could not be opened for saving.",
            )
        }
        label
    }

    /**
     * Provider display name of [treeUri], or `null` when the app no longer
     * holds a usable grant or the document is gone.
     */
    suspend fun treeLabel(
        context: Context,
        treeUri: Uri,
        requireWriteGrant: Boolean = true,
    ): String? = withContext(Dispatchers.IO) {
        if (requireWriteGrant && !hasPersistedWrite(context, treeUri)) return@withContext null
        val documentUri = try {
            DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
        } catch (e: Exception) {
            return@withContext null
        }
        val cursor = try {
            context.contentResolver.query(
                documentUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )
        } catch (e: Exception) {
            return@withContext null
        }
        cursor?.use {
            if (it.moveToFirst()) return@withContext it.getString(0)
        }
        null
    }

    /** Whether the app holds persisted read+write access for [treeUri]. */
    fun hasPersistedWrite(context: Context, treeUri: Uri): Boolean = try {
        context.contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission && it.isWritePermission
        }
    } catch (e: SecurityException) {
        false
    }

    /** Releases a grant the app no longer needs. Best effort. */
    suspend fun releaseTree(context: Context, treeUri: Uri) = withContext(Dispatchers.IO) {
        try {
            context.contentResolver.releasePersistableUriPermission(
                treeUri,
                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            // Already gone or never persisted.
        }
    }

    private fun saveToMediaStore(
        context: Context,
        source: File,
        folderName: String,
        mimeType: String,
    ): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, source.name)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                "${Environment.DIRECTORY_PICTURES}/$folderName",
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        // minSdk 29 → RELATIVE_PATH / IS_PENDING are always available and an
        // app-owned insert needs no storage permission.
        val uri = try {
            resolver.insert(mediaCollection, values)
        } catch (e: Exception) {
            throw mapFailure(e)
        } ?: throw DownloadFailure("io", "Could not create the download file.")

        try {
            copyToUri(context, source, uri)
            val publish = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            // A row that no longer exists (deleted by the media provider or a
            // cleanup) must not be reported as a saved wallpaper.
            val published = resolver.update(uri, publish, null, null)
            if (published != 1) {
                throw DownloadFailure(
                    "io",
                    "Could not finish saving the wallpaper.",
                )
            }
            return uri
        } catch (e: Exception) {
            // A failed write must never leave a half-written gallery row.
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            throw mapFailure(e)
        }
    }

    private fun saveToTree(
        context: Context,
        source: File,
        treeUri: Uri,
        folderName: String,
        mimeType: String,
    ): Uri {
        if (!hasPersistedWrite(context, treeUri)) {
            throw DownloadFailure(
                "noPermission",
                "Access to the download folder was lost.",
            )
        }
        val documentUri = try {
            DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
        } catch (e: Exception) {
            throw DownloadFailure(
                "destinationUnavailable",
                "The download folder is no longer available.",
                e,
            )
        }
        val folderUri = findOrCreateFolder(context, treeUri, documentUri, folderName)
        val fileUri = try {
            DocumentsContract.createDocument(
                context.contentResolver,
                folderUri,
                mimeType,
                source.name,
            )
        } catch (e: Exception) {
            throw mapFailure(e)
        } ?: throw DownloadFailure("io", "Could not create the download file.")

        try {
            copyToUri(context, source, fileUri)
            return fileUri
        } catch (e: Exception) {
            // Remove the partial document: a half-copied image in the user's
            // folder is worse than a failed download.
            try {
                DocumentsContract.deleteDocument(context.contentResolver, fileUri)
            } catch (_: Exception) {
            }
            throw mapFailure(e)
        }
    }

    private fun findOrCreateFolder(
        context: Context,
        treeUri: Uri,
        documentUri: Uri,
        folderName: String,
    ): Uri {
        val resolver = context.contentResolver
        val treeDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, treeDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        val cursor = try {
            resolver.query(childrenUri, projection, null, null, null)
        } catch (e: Exception) {
            throw mapFailure(e)
        } ?: throw DownloadFailure(
            "destinationUnavailable",
            "The download folder is no longer available.",
        )

        cursor.use {
            while (it.moveToNext()) {
                val name = it.getString(1)
                val mime = it.getString(2)
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR &&
                    name == folderName
                ) {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        it.getString(0),
                    )
                }
            }
        }

        return try {
            DocumentsContract.createDocument(
                resolver,
                documentUri,
                DocumentsContract.Document.MIME_TYPE_DIR,
                folderName,
            )
        } catch (e: Exception) {
            throw mapFailure(e)
        } ?: throw DownloadFailure(
            "io",
            "Could not create the $folderName folder.",
        )
    }

    private fun copyToUri(context: Context, source: File, target: Uri) {
        val output: OutputStream = context.contentResolver.openOutputStream(target, "w")
            ?: throw DownloadFailure("io", "Could not open the destination file.")
        output.use { out ->
            input(source).use { it.copyTo(out, DEFAULT_BUFFER_SIZE) }
            out.flush()
        }
    }

    private fun input(source: File): InputStream = FileInputStream(source)

    private fun mapFailure(error: Throwable): DownloadFailure = when {
        error is DownloadFailure -> error
        error is SecurityException -> DownloadFailure(
            "noPermission",
            "Access to the download folder was lost.",
            error,
        )
        error is java.io.FileNotFoundException ->
            DownloadFailure("notFound", "The downloaded file is missing.", error)
        error is IllegalArgumentException -> DownloadFailure(
            "destinationUnavailable",
            "The download folder is no longer available.",
            error,
        )
        error is IOException && isOutOfSpace(error) -> DownloadFailure(
            "noSpace",
            "Not enough storage space to save the wallpaper.",
            error,
        )
        error is IOException -> DownloadFailure(
            "io",
            "Could not write the wallpaper to the download folder.",
            error,
        )
        else -> DownloadFailure(
            "io",
            error.message ?: "Could not save the wallpaper.",
            error,
        )
    }

    private fun isOutOfSpace(error: IOException): Boolean {
        val message = error.message ?: return false
        return message.contains("ENOSPC", ignoreCase = true) ||
            message.contains("No space left", ignoreCase = true)
    }
}
