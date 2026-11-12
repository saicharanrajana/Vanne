package com.saicharanrajana.vanne

import android.app.Application
import android.content.res.Configuration
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel

class WallpaperApp : Application() {
    private var paletteChanges: MethodChannel? = null

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Application resources are updated before this callback. Unlike an
        // Activity listener, this survives recreation with the cached engine.
        paletteChanges?.invokeMethod("changed", null)
    }

    override fun onCreate() {
        super.onCreate()
        // Pre-warm and cache the FlutterEngine so it survives Activity
        // recreation (e.g. RRO overlay change from wallpaper → dynamic color).
        // Without this, WallpaperManager → MagicPortrait → systemui-dynamic.frro
        // triggers AppCompatResourceOverlayPolicy recreation and Flutter loses state.
        val engine = FlutterEngine(this)
        paletteChanges = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "com.saicharanrajana.vanne/dynamic_palette"
        )
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        GeneratedPluginRegistrant.registerWith(engine)
        FlutterEngineCache.getInstance().put("main_engine", engine)
    }
}
