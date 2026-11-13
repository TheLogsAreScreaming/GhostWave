package org.ghostwave.ghostwave_app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The one Flutter engine. Held here rather than by the activity, so the single Dart isolate
 * (link, chat history, acks, notifications) carries on while no UI exists.
 */
object GhostWaveEngine {
    private const val CHANNEL = "org.ghostwave/background_link"

    /** Long enough for Dart's debounced history save to finish after a disconnect. */
    private const val IDLE_DESTROY_DELAY_MS = 1500L

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    /** Whether an activity currently owns the UI. */
    @Volatile
    var activityAttached = false

    /** The running engine, or a new one with plugins registered. */
    fun obtain(context: Context): FlutterEngine {
        engine?.let { return it }
        val app = context.applicationContext
        val created = FlutterEngine(app)
        created.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}

            override fun onEngineWillDestroy() {
                engine = null
                channel = null
                HomeSurfaces.detach()
            }
        })
        val methods = MethodChannel(created.dartExecutor.binaryMessenger, CHANNEL)
        methods.setMethodCallHandler { call, result -> handle(app, call, result) }
        HomeSurfaces.attach(app, created.dartExecutor.binaryMessenger)
        engine = created
        channel = methods
        return created
    }

    /** The notification's Disconnect button: Dart does it, then stops the service. */
    fun requestDisconnect() {
        channel?.invokeMethod("disconnectRequested", null)
    }

    /** The UI is gone but the engine stays: the GPS plugin drops its updates with the activity. */
    fun reportActivityGone() {
        channel?.invokeMethod("activityGone", null)
    }

    /** Tells Dart whether the service may read the GPS in the background. */
    fun reportLocationGrant(granted: Boolean) {
        channel?.invokeMethod("locationGrant", granted)
    }

    /** After the service stops: with no UI left, nothing needs the engine. */
    fun destroyIfIdle() {
        Handler(Looper.getMainLooper()).postDelayed({
            if (!activityAttached && !LinkForegroundService.isRunning) engine?.destroy()
        }, IDLE_DESTROY_DELAY_MS)
    }

    private fun handle(app: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> try {
                LinkForegroundService.start(
                    app,
                    call.argument("title") ?: "",
                    call.argument("text") ?: "",
                    call.argument("location") ?: false,
                )
                result.success(true)
            } catch (e: IllegalStateException) {
                // Android refuses to start a foreground service from the background.
                result.success(false)
            } catch (e: SecurityException) {
                result.success(false)
            }
            "update" -> {
                LinkForegroundService.update(call.argument("title") ?: "", call.argument("text") ?: "")
                result.success(null)
            }
            "stop" -> {
                LinkForegroundService.stop(app)
                result.success(null)
            }
            "batteryExempt" -> {
                val power = app.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(power.isIgnoringBatteryOptimizations(app.packageName))
            }
            "requestBatteryExemption" -> {
                requestBatteryExemption(app)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // Only reached from the explanation screen, after the user tapped to allow it.
    @SuppressLint("BatteryLife")
    private fun requestBatteryExemption(app: Context) {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${app.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        app.startActivity(intent)
    }
}
