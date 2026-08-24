package com.example.wallpaper_app

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

class WallpaperApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Pre-warm and cache the FlutterEngine so it survives Activity
        // recreation (e.g. RRO overlay change from wallpaper → dynamic color).
        // Without this, WallpaperManager → MagicPortrait → systemui-dynamic.frro
        // triggers AppCompatResourceOverlayPolicy recreation and Flutter loses state.
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        GeneratedPluginRegistrant.registerWith(engine)
        FlutterEngineCache.getInstance().put("main_engine", engine)
    }
}
