package org.ghostwave.ghostwave_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * App-icon shortcuts and the home-screen widget. Both only open the app at a place
 * (`ghostwave://open/<action>`): nothing is sent from the home screen, and an SOS
 * still needs the hold on the SOS screen.
 */
object HomeSurfaces {
    private const val LAUNCH_CHANNEL = "org.ghostwave/launch"
    private const val WIDGET_CHANNEL = "org.ghostwave/home_widget"
    private const val PREFS = "ghostwave_widget"

    /** The only places a shortcut or the widget may open. */
    val ACTIONS = setOf("sos", "checkin", "chats")

    private var launch: MethodChannel? = null

    @Volatile
    private var pending: String? = null

    /** Wires both channels to a new engine. */
    fun attach(app: Context, messenger: BinaryMessenger) {
        launch = MethodChannel(messenger, LAUNCH_CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    // read once: an action is handled exactly once
                    "takePending" -> result.success(synchronized(this) { pending.also { pending = null } })
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(messenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putString("status", call.argument<String>("status") ?: "")
                        .putString("detail", call.argument<String>("detail") ?: "")
                        .putBoolean("alert", call.argument<Boolean>("alert") ?: false)
                        .apply()
                    refreshWidgets(app)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun detach() {
        launch = null
    }

    /** The action an intent asks for, if it is one of [ACTIONS]. */
    fun actionOf(intent: Intent?): String? {
        val data = intent?.data ?: return null
        if (data.scheme != "ghostwave" || data.host != "open") return null
        return data.lastPathSegment?.takeIf { it in ACTIONS }
    }

    /** Remembers [action] and tells Dart to come and take it. */
    fun deliver(action: String) {
        synchronized(this) { pending = action }
        launch?.invokeMethod("ping", null)
    }

    /** An intent that opens the app at [action]. */
    fun openIntent(context: Context, action: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("ghostwave://open/$action"), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    fun widgetText(context: Context): Triple<String, String, Boolean> {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return Triple(
            p.getString("status", null) ?: "Open GhostWave to connect",
            p.getString("detail", null) ?: "",
            p.getBoolean("alert", false),
        )
    }

    fun refreshWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, StatusWidget::class.java))
        if (ids.isNotEmpty()) StatusWidget.render(context, manager, ids)
    }
}
