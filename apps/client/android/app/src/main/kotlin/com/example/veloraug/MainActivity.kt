package com.example.veloraug

import android.Manifest
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Downloads, Step 12A: hands each movie's .mp4 to Android's own download
 * manager, which saves it to Downloads/VeloraUG, shows a notification,
 * carries on in the background and after a dropped connection, and keeps
 * the file when the app is uninstalled. See lib/downloads/.
 *
 * A FlutterFragmentActivity, which local_auth needs for App lock's system
 * prompt. It also tells Settings whether Android allows VeloraUG to show
 * notifications; it never asks, because no push service is set up yet.
 */
class MainActivity : FlutterFragmentActivity() {
    private var waitingForPermission: (() -> Unit)? = null
    private var refusedPermission: (() -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "veloraug/downloads")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> start(call, result)
                        "status" -> result.success(status(call.argument<List<String>>("ids") ?: emptyList()))
                        "open" -> result.success(open(call.argument<String>("id")))
                        "remove" -> {
                            idOf(call.argument<String>("id"))?.let { manager().remove(it) }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("failed", error.javaClass.simpleName, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "veloraug/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Whether Android lets VeloraUG show notifications now:
                    // the app's switch in Android's settings, and on Android
                    // 13 and newer the notification permission.
                    "allowed" -> result.success(
                        NotificationManagerCompat.from(this).areNotificationsEnabled(),
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun manager() = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun idOf(text: String?): Long? = text?.toLongOrNull()

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val fileName = call.argument<String>("fileName")
        val title = call.argument<String>("title") ?: "VeloraUG"
        val uri = url?.let { Uri.parse(it) }
        // Only http(s), and a plain file name: never a folder.
        if (uri == null || (uri.scheme != "https" && uri.scheme != "http") ||
            fileName == null || !SAFE_NAME.matches(fileName)
        ) {
            result.error("failed", "Not a download VeloraUG makes", null)
            return
        }
        withStoragePermission(
            granted = {
                val request = DownloadManager.Request(uri)
                    .setTitle(title)
                    .setDescription(fileName)
                    .setMimeType("video/mp4")
                    .setNotificationVisibility(
                        DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
                    )
                    .setDestinationInExternalPublicDir(
                        Environment.DIRECTORY_DOWNLOADS,
                        "VeloraUG/$fileName",
                    )
                    .setAllowedOverMetered(true)
                    .setAllowedOverRoaming(true)
                try {
                    result.success(manager().enqueue(request).toString())
                } catch (error: Exception) {
                    result.error("failed", error.javaClass.simpleName, null)
                }
            },
            refused = { result.error("permission", "Storage permission refused", null) },
        )
    }

    private fun status(ids: List<String>): List<Map<String, Any>> {
        val numbers = ids.mapNotNull { it.toLongOrNull() }.toLongArray()
        if (numbers.isEmpty()) return emptyList()
        val found = mutableListOf<Map<String, Any>>()
        manager().query(DownloadManager.Query().setFilterById(*numbers))?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            val statusColumn = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            val reasonColumn = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)
            val bytesColumn = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val totalColumn = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            while (cursor.moveToNext()) {
                val reason = cursor.getInt(reasonColumn)
                val status = cursor.getInt(statusColumn)
                val state = when (status) {
                    DownloadManager.STATUS_PENDING -> "waiting"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    DownloadManager.STATUS_SUCCESSFUL -> "done"
                    else -> "failed"
                }
                found.add(
                    mapOf(
                        "id" to cursor.getLong(idColumn).toString(),
                        "state" to state,
                        "bytes" to cursor.getLong(bytesColumn),
                        "total" to cursor.getLong(totalColumn),
                        "noRoom" to (state == "failed" &&
                            reason == DownloadManager.ERROR_INSUFFICIENT_SPACE),
                        // Why a paused download is waiting.
                        "wait" to when {
                            status != DownloadManager.STATUS_PAUSED -> ""
                            reason == DownloadManager.PAUSED_WAITING_FOR_NETWORK ||
                                reason == DownloadManager.PAUSED_QUEUED_FOR_WIFI -> "network"
                            reason == DownloadManager.PAUSED_WAITING_TO_RETRY -> "retry"
                            else -> "other"
                        },
                    ),
                )
            }
        }
        return found
    }

    private fun open(text: String?): Boolean {
        val id = idOf(text) ?: return false
        val uri = manager().getUriForDownloadedFile(id) ?: return false
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "video/mp4")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (error: ActivityNotFoundException) {
            false
        }
    }

    /** Android 9 and older need permission to write to Downloads. */
    private fun withStoragePermission(granted: () -> Unit, refused: () -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            granted()
            return
        }
        waitingForPermission = granted
        refusedPermission = refused
        requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), STORAGE_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_REQUEST) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        val next = if (granted) waitingForPermission else refusedPermission
        waitingForPermission = null
        refusedPermission = null
        next?.invoke()
    }

    companion object {
        private const val STORAGE_REQUEST = 4127
        private val SAFE_NAME = Regex("^[A-Za-z0-9 .,'()-]{1,160}\\.mp4$")
    }
}
