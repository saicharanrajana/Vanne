package com.example.system_wallpaper

import android.app.WallpaperManager
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class SystemWallpaperPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var appContext: Context? = null
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
        channel.setMethodCallHandler(null)
        scope.cancel()
        appContext = null
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
                val ctx = appContext
                if (ctx == null) {
                    result.error("noContext", "Plugin not attached", null)
                    return
                }
                val ok = WallpaperHandler.setWithSystemPicker(ctx, path)
                if (ok) {
                    result.success(mapOf("success" to true))
                } else {
                    result.error("unsupported", "No app found to handle wallpaper picker", null)
                }
            }

            else -> result.notImplemented()
        }
    }
}
