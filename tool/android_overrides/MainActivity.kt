package com.saicharanrajana.vanne

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    /**
     * Binds to the engine pre-warmed and cached by [WallpaperApp].
     *
     * Because the engine comes from the cache, FlutterActivity treats it as
     * host-provided and skips its own plugin registration; the plugins were
     * already registered when [WallpaperApp] constructed the engine. Reporting
     * the engine through `provideFlutterEngine` as well would be dead code:
     * that hook is only consulted when [getCachedEngineId] returns null.
     */
    override fun getCachedEngineId(): String = WallpaperApp.ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean {
        // Keep engine alive across Activity recreation (RRO overlay)
        return false
    }
}
