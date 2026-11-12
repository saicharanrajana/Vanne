package com.saicharanrajana.vanne

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get("main_engine")
    }

    override fun getCachedEngineId(): String? {
        return "main_engine"
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        // Keep engine alive across Activity recreation (RRO overlay)
        return false
    }
}
