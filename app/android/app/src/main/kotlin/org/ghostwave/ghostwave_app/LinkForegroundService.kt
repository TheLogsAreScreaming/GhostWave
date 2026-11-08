package org.ghostwave.ghostwave_app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the process, and the CPU, running while a node link is wanted. It holds no link logic:
 * the TCP or Bluetooth link stays in Dart. Started and stopped only by `BackgroundLinkManager`.
 */
class LinkForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    // Not sticky: a restarted service would have no Dart side behind it.
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISCONNECT) {
            GhostWaveEngine.requestDisconnect()
            return START_NOT_STICKY
        }
        title = intent?.getStringExtra(EXTRA_TITLE) ?: title
        text = intent?.getStringExtra(EXTRA_TEXT) ?: text
        createChannel()
        val notification = build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = this
        acquireWakeLock()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
        GhostWaveEngine.destroyIfIdle()
    }

    // No timeout: the wake lock lasts exactly as long as the service, and the explanation
    // screen tells the user what that costs. Reconnects and heartbeats stall without it.
    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GhostWave:link").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(CHANNEL_ID, "Background connection", NotificationManager.IMPORTANCE_LOW)
        channel.description = "Shown while GhostWave keeps your node connected"
        channel.setShowBadge(false)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun build(): Notification {
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val open = PendingIntent.getActivity(this, 0, packageManager.getLaunchIntentForPackage(packageName), flags)
        val disconnect = PendingIntent.getService(
            this,
            1,
            Intent(this, LinkForegroundService::class.java).setAction(ACTION_DISCONNECT),
            flags,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_ghostwave)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Disconnect", disconnect).build())
            .build()
    }

    private fun refresh() {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, build())
    }

    companion object {
        private const val CHANNEL_ID = "background_link"
        private const val NOTIFICATION_ID = 7001
        private const val ACTION_DISCONNECT = "org.ghostwave.action.DISCONNECT"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"

        private var running: LinkForegroundService? = null
        private var title = "GhostWave connected"
        private var text = ""

        /** Whether the service is up, so the engine has to outlive the activity. */
        val isRunning: Boolean get() = running != null

        /** Starts it; Android throws if the app may not start one from the background. */
        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, LinkForegroundService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** Changes the persistent notification's wording. */
        fun update(newTitle: String, newText: String) {
            title = newTitle
            text = newText
            running?.refresh()
        }

        /** Stops it. Safe when it is not running. */
        fun stop(context: Context) {
            context.stopService(Intent(context, LinkForegroundService::class.java))
        }
    }
}
