package com.example.system_wallpaper

import android.app.WallpaperManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object WallpaperHandler {
    suspend fun setWallpaper(
        context: Context,
        path: String,
        flags: Int,
    ): Result<Unit> = withContext(Dispatchers.IO) {
        val file = File(path)
        if (!file.exists()) {
            return@withContext Result.failure(FileNotFoundException("File not found: $path"))
        }
        try {
            val wm = WallpaperManager.getInstance(context)
            // Use buffered stream and allowBackup=false to avoid BackupManager
            // work that can trigger ANR/restarts on some OEMs.
            FileInputStream(file).buffered().use { ins ->
                // minSdk 29 → FLAG_LOCK / FLAG_SYSTEM always available.
                @Suppress("DEPRECATION")
                wm.setStream(ins, null, false, flags)
            }
            Result.success(Unit)
        } catch (e: SecurityException) {
            Result.failure(e)
        } catch (e: IOException) {
            Result.failure(e)
        } catch (e: IllegalArgumentException) {
            // Bad bitmap / decode failure.
            Result.failure(IOException("Failed to decode wallpaper: ${e.message}", e))
        } catch (e: OutOfMemoryError) {
            Result.failure(IOException("Wallpaper too large: ${e.message}", e))
        }
    }

    fun setWithSystemPicker(
        context: Context,
        path: String,
    ): Boolean {
        val rawFile = File(path)
        if (!rawFile.exists()) return false

        var resolvedFile: File = rawFile
        val uri = try {
            FileProvider.getUriForFile(
                context,
                "${context.packageName}.system_wallpaper.fileprovider",
                resolvedFile,
            )
        } catch (e: IllegalArgumentException) {
            try {
                val fallbackDir = File(context.cacheDir, "wallpaper_share").apply { mkdirs() }
                val fallback = File(fallbackDir, rawFile.name)
                rawFile.copyTo(fallback, overwrite = true)
                resolvedFile = fallback
                FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.system_wallpaper.fileprovider",
                    resolvedFile,
                )
            } catch (_: Exception) {
                return false
            }
        }

        val pm = context.packageManager

        fun isResolvable(intent: Intent): Boolean {
            return try {
                pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY).isNotEmpty()
            } catch (_: Exception) {
                false
            }
        }

        // Build candidates in priority order.
        // Direct crop intent first — avoids MagicPortrait live-wallpaper path
        // that triggers RRO overlay recreation (see log: MagicPortraitWallpaperService → as.24→as.25)
        // ATTACH_DATA via Photos → Wallpaper picker → MagicPortrait causes restart.
        val candidates = mutableListOf<Intent>()

        // 1. WallpaperManager.getCropAndSetWallpaperIntent (ImageWallpaper, no live service)
        try {
            val cropIntent = WallpaperManager.getInstance(context).getCropAndSetWallpaperIntent(uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newRawUri(null, uri)
            }
            candidates.add(cropIntent)
        } catch (_: Exception) {
        }

        // 2. Google Photos-style ATTACH_DATA (fallback, may trigger MagicPortrait)
        candidates.add(
            Intent(Intent.ACTION_ATTACH_DATA).apply {
                addCategory(Intent.CATEGORY_DEFAULT)
                setDataAndType(uri, "image/*")
                putExtra("mimeType", "image/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                clipData = ClipData.newRawUri(null, uri)
            }
        )

        // 3. ACTION_SET_WALLPAPER (generic)
        candidates.add(
            Intent(Intent.ACTION_SET_WALLPAPER).apply {
                setDataAndType(uri, "image/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                clipData = ClipData.newRawUri(null, uri)
            }
        )

        // 4. ACTION_VIEW fallback (any image viewer that can set as wallpaper)
        candidates.add(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "image/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                clipData = ClipData.newRawUri(null, uri)
            }
        )

        // Find first resolvable candidate.
        var toLaunch: Intent? = null
        for (intent in candidates) {
            if (isResolvable(intent)) {
                toLaunch = intent
                break
            }
        }

        if (toLaunch == null) return false

        // Grant to all resolved handlers so chooser targets can read.
        try {
            val resInfos = pm.queryIntentActivities(toLaunch, PackageManager.MATCH_DEFAULT_ONLY)
            for (info in resInfos) {
                context.grantUriPermission(
                    info.activityInfo.packageName,
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        } catch (_: Exception) {
        }

        // If multiple handlers, use chooser for better UX.
        val launchIntent = try {
            val count = pm.queryIntentActivities(toLaunch, PackageManager.MATCH_DEFAULT_ONLY).size
            if (count > 1) {
                Intent.createChooser(toLaunch, "Set wallpaper with").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            } else {
                toLaunch
            }
        } catch (_: Exception) {
            toLaunch
        }

        return try {
            context.startActivity(launchIntent)
            true
        } catch (_: Exception) {
            // Try without chooser as fallback.
            try {
                context.startActivity(toLaunch)
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
