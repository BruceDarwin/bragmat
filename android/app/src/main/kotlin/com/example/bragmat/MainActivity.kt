package com.example.bragmat

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "bragmat/saf"
    private val requestPick = 9101
    private val requestExport = 9102

    private var pendingResult: MethodChannel.Result? = null
    private var pendingExportSource: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickBackup" -> {
                        if (!beginRequest(result)) return@setMethodCallHandler
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                arrayOf("application/zip", "application/octet-stream")
                            )
                        }
                        startActivityForResult(intent, requestPick)
                    }
                    "exportBackup" -> {
                        if (!beginRequest(result)) return@setMethodCallHandler
                        pendingExportSource = call.argument<String>("path")
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/zip"
                            putExtra(
                                Intent.EXTRA_TITLE,
                                call.argument<String>("name") ?: "bragmat_backup.zip"
                            )
                        }
                        startActivityForResult(intent, requestExport)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun beginRequest(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) {
            result.error("busy", "A document picker request is already active", null)
            return false
        }
        pendingResult = result
        return true
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestPick && requestCode != requestExport) return

        val result = pendingResult
        val exportSource = pendingExportSource
        pendingResult = null
        pendingExportSource = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            // User cancelled — report cleanly to Dart.
            result.success(if (requestCode == requestPick) null else false)
            return
        }

        val uri: Uri = data.data!!
        try {
            if (requestCode == requestPick) {
                val outFile =
                    File(cacheDir, "picked_backup_${System.currentTimeMillis()}.zip")
                contentResolver.openInputStream(uri).use { input ->
                    if (input == null) {
                        result.error("saf_error", "Could not open selected document", null)
                        return
                    }
                    FileOutputStream(outFile).use { output -> input.copyTo(output) }
                }
                result.success(outFile.absolutePath)
            } else {
                if (exportSource == null) {
                    result.success(false)
                    return
                }
                contentResolver.openOutputStream(uri).use { output ->
                    if (output == null) {
                        result.error("saf_error", "Could not open destination", null)
                        return
                    }
                    File(exportSource).inputStream().use { input ->
                        input.copyTo(output)
                    }
                }
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("saf_error", e.message, null)
        }
    }
}
