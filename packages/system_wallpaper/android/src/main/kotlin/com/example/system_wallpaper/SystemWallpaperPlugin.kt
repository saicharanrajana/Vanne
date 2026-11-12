package com.example.system_wallpaper

import android.app.Activity
import android.app.WallpaperManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.io.FileNotFoundException
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class SystemWallpaperPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var appContext: Context? = null

    // Only valid while the host activity is attached. Replaced on
    // reattachment because the previous instance is destroyed.
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    // One folder picker at a time. Survives a configuration-change
    // reattachment (Android re-delivers the result to the new activity) and is
    // completed with an error if the activity goes away for good.
    private var pendingPick: MethodChannel.Result? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // TODO(guard): add a "verifyOverrides" method here that reports whether the
    //  app-level overrides are applied (FlutterEngineCache contains "main_engine"
    //  AND the running activity binds to it). The Dart side (bootstrap) should
    //  call it once at startup in debug builds and log a loud warning if it
    //  fails — that catches a forgotten `tool/apply_android_overrides.sh` run
    //  after recreating android/. See ARCHITECTURE.md → "App-level Android
    //  overrides".

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "system_wallpaper")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        completePickWithError(
            "noActivity",
            "The folder picker was closed because the app is shutting down.",
        )
        channel.setMethodCallHandler(null)
        scope.cancel()
        appContext = null
        activity = null
        activityBinding = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Keep [pendingPick]: the result is delivered to the recreated
        // activity, and dropping it here would strand the Dart future.
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
        completePickWithError(
            "noActivity",
            "The folder picker was closed because the app left the foreground.",
        )
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != PICK_REQUEST_CODE) return false
        val pending = pendingPick ?: return true
        pendingPick = null

        if (resultCode != Activity.RESULT_OK) {
            pending.success(mapOf("canceled" to true))
            return true
        }
        val treeUri = data?.data
        val context = appContext
        if (treeUri == null || context == null) {
            pending.success(mapOf("canceled" to true))
            return true
        }
        val takeFlags = data.flags and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        // Validation touches the provider, so keep it off the main thread.
        scope.launch {
            try {
                val label = DownloadHandler.adoptTree(context, treeUri, takeFlags)
                pending.success(
                    mapOf(
                        "treeUri" to treeUri.toString(),
                        "label" to label,
                    ),
                )
            } catch (e: DownloadFailure) {
                pending.error(e.code, e.message, null)
            } catch (e: Exception) {
                pending.error("noWriteAccess", e.message, null)
            }
        }
        return true
    }

    private fun completePickWithError(code: String, message: String) {
        val pending = pendingPick ?: return
        pendingPick = null
        pending.error(code, message, null)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "setWallpaper" -> {
                val path = call.argument<String>("path")
                val target = call.argument<String>("target")
                if (path.isNullOrBlank()) {
                    result.error("invalidArgs", "path is required", null)
                    return
                }
                if (target.isNullOrBlank()) {
                    result.error("invalidArgs", "target is required (home|lock|both)", null)
                    return
                }
                val flags = when (target) {
                    "home" -> WallpaperManager.FLAG_SYSTEM
                    "lock" -> WallpaperManager.FLAG_LOCK
                    "both" -> WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK
                    else -> {
                        result.error("invalidArgs", "unknown target: $target", null)
                        return
                    }
                }
                val ctx = appContext
                if (ctx == null) {
                    result.error("noContext", "Plugin not attached", null)
                    return
                }
                scope.launch {
                    val r = WallpaperHandler.setWallpaper(ctx, path, flags)
                    r.fold(
                        onSuccess = { result.success(mapOf("success" to true)) },
                        onFailure = { e ->
                            val code = when (e) {
                                is FileNotFoundException -> "fileNotFound"
                                is SecurityException -> "security"
                                is IOException -> "io"
                                else -> "unknown"
                            }
                            result.error(code, e.message, null)
                        },
                    )
                }
            }

            "setWithSystemPicker" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("invalidArgs", "path is required", null)
                    return
                }
                // The picker is a user-initiated activity launch and must come
                // from the attached activity so it stays in this task and can
                // return here. An application context cannot do that, and a
                // cached engine can still hold a host that is shutting down.
                val host = activity
                if (host == null || host.isFinishing || host.isDestroyed) {
                    result.error(
                        "noActivity",
                        "Open the app in the foreground and try again.",
                        null,
                    )
                    return
                }
                val ok = WallpaperHandler.setWithSystemPicker(host, path)
                if (ok) {
                    result.success(mapOf("success" to true))
                } else {
                    result.error("unsupported", "No app found to handle wallpaper picker", null)
                }
            }

            "downloads.save" -> handleSave(call, result)

            "downloads.pickParent" -> handlePickParent(result)

            "downloads.checkParent" -> handleCheckParent(call, result)

            "downloads.releaseParent" -> handleReleaseParent(call, result)

            else -> result.notImplemented()
        }
    }

    /** Writes one wallpaper into the default Pictures folder or a chosen tree. */
    private fun handleSave(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val path = call.argument<String>("path")
        val folderName = call.argument<String>("folderName")
        val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
        val treeUri = call.argument<String>("treeUri")?.takeIf { it.isNotBlank() }
        val context = appContext
        if (path.isNullOrBlank() || folderName.isNullOrBlank()) {
            result.error("invalidArgs", "path and folderName are required", null)
            return
        }
        if (folderName.contains('/') || folderName.contains('\\')) {
            result.error("invalidArgs", "folderName must be a single segment", null)
            return
        }
        if (context == null) {
            result.error("noContext", "Plugin not attached", null)
            return
        }
        val source = java.io.File(path)
        scope.launch {
            try {
                val uri = DownloadHandler.save(
                    context = context,
                    source = source,
                    folderName = folderName,
                    mimeType = mimeType,
                    treeUri = treeUri?.let { Uri.parse(it) },
                )
                result.success(mapOf("uri" to uri.toString()))
            } catch (e: DownloadFailure) {
                result.error(e.code, e.message, null)
            } catch (e: Exception) {
                result.error("io", e.message, null)
            }
        }
    }

    /**
     * Opens the system folder picker from the attached activity.
     *
     * No `NEW_TASK`: the picker belongs to this task and returns here. A
     * second request while one is open is refused instead of replacing the
     * pending result.
     */
    private fun handlePickParent(result: MethodChannel.Result) {
        val host = activity
        if (host == null || host.isFinishing || host.isDestroyed) {
            result.error(
                "noActivity",
                "Open the app in the foreground and try again.",
                null,
            )
            return
        }
        if (pendingPick != null) {
            result.error("busy", "A folder picker is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        pendingPick = result
        try {
            host.startActivityForResult(intent, PICK_REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.error(
                "unsupported",
                "No folder picker is available on this device.",
                null,
            )
        } catch (e: Exception) {
            pendingPick = null
            result.error("unsupported", e.message, null)
        }
    }

    /** Reports whether a persisted tree still grants read+write access. */
    private fun handleCheckParent(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val treeUri = call.argument<String>("treeUri")
        val context = appContext
        if (treeUri.isNullOrBlank() || context == null) {
            result.error("invalidArgs", "treeUri is required", null)
            return
        }
        scope.launch {
            val label = try {
                DownloadHandler.treeLabel(context, Uri.parse(treeUri))
            } catch (e: Exception) {
                null
            }
            if (label == null) {
                result.success(mapOf("available" to false))
            } else {
                result.success(mapOf("available" to true, "label" to label))
            }
        }
    }

    private fun handleReleaseParent(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val treeUri = call.argument<String>("treeUri")
        val context = appContext
        if (treeUri.isNullOrBlank() || context == null) {
            result.error("invalidArgs", "treeUri is required", null)
            return
        }
        scope.launch {
            DownloadHandler.releaseTree(context, Uri.parse(treeUri))
            result.success(null)
        }
    }

    private companion object {
        /** Request code owned by this plugin's folder picker. */
        const val PICK_REQUEST_CODE = 0x5D1E
    }
}
