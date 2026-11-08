package org.ghostwave.ghostwave_app

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** The UI. It borrows the shared engine, which can outlive it while the link service runs. */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        GhostWaveEngine.activityAttached = true
        super.onCreate(savedInstanceState)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine = GhostWaveEngine.obtain(context)

    // Swiping the app away must not end the Dart side while the link is being kept alive.
    override fun shouldDestroyEngineWithHost(): Boolean = !LinkForegroundService.isRunning

    override fun onDestroy() {
        super.onDestroy()
        GhostWaveEngine.activityAttached = false
    }
}
