package org.ghostwave.ghostwave_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/** The UI. It borrows the shared engine, which can outlive it while the link service runs. */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        GhostWaveEngine.activityAttached = true
        super.onCreate(savedInstanceState)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine = GhostWaveEngine.obtain(context)

    // Swiping the app away must not end the Dart side while the link is being kept alive.
    override fun shouldDestroyEngineWithHost(): Boolean = !LinkForegroundService.isRunning

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL)
            .setMethodCallHandler(::handleFiles)
    }

    override fun onDestroy() {
        super.onDestroy()
        GhostWaveEngine.activityAttached = false
    }

    // The system's document picker: no storage permission, and the user chooses the place.
    private fun handleFiles(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "A file chooser is already open", null)
            return
        }
        when (call.method) {
            "save" -> {
                pendingBytes = call.argument<ByteArray>("bytes")
                pendingResult = result
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(MIME)
                    .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                startActivityForResult(intent, REQUEST_SAVE)
            }
            "pick" -> {
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*")
                startActivityForResult(intent, REQUEST_PICK)
            }
            else -> result.notImplemented()
        }
    }

    @Deprecated("Deprecated in Android; FlutterActivity still dispatches through it")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_SAVE && requestCode != REQUEST_PICK) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingResult ?: return
        val bytes = pendingBytes
        pendingResult = null
        pendingBytes = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(if (requestCode == REQUEST_SAVE) false else null)
            return
        }
        Thread {
            try {
                val answer: Any? = if (requestCode == REQUEST_SAVE) write(uri, bytes ?: ByteArray(0)) else read(uri)
                runOnUiThread { result.success(answer) }
            } catch (e: IOException) {
                runOnUiThread { result.error("io", e.message, null) }
            } catch (e: SecurityException) {
                runOnUiThread { result.error("io", e.message, null) }
            }
        }.start()
    }

    private fun write(uri: Uri, bytes: ByteArray): Boolean {
        val out = contentResolver.openOutputStream(uri, "wt") ?: throw IOException("Can't write to that location")
        out.use { it.write(bytes) }
        return true
    }

    private fun read(uri: Uri): ByteArray {
        val input = contentResolver.openInputStream(uri) ?: throw IOException("Can't read that file")
        return input.use { it.readBytes() }
    }

    private companion object {
        const val FILES_CHANNEL = "org.ghostwave/backup_files"
        const val MIME = "application/octet-stream"
        const val REQUEST_SAVE = 7101
        const val REQUEST_PICK = 7102
    }
}
