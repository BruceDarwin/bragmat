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
    private val galleryChannelName = "bragmat/gallery_picker"
    private val requestPick = 9101
    private val requestExport = 9102
    private val requestGalleryPick = 9103

    private var pendingResult: MethodChannel.Result? = null
    private var pendingExportSource: String? = null

    // Gallery picker state. The result record is persisted before Dart is
    // notified so a pick delivered after activity/process death can be
    // recovered later via "retrievePending". It survives until Dart
    // acknowledges staging; a new pick never clears it.
    private var pendingGalleryResult: MethodChannel.Result? = null
    private var pendingGalleryContext: String? = null

    private val galleryPrefs by lazy {
        getSharedPreferences("bragmat_gallery_picker", MODE_PRIVATE)
    }

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, galleryChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> handleGalleryPick(call, result)
                    "retrievePending" -> result.success(readPendingGalleryRecord())
                    "takeInterrupted" -> {
                        // A stale in_progress marker means a pick's result
                        // was never delivered (e.g. process death closed the
                        // picker without returning to the activity). Report
                        // it once so the user can be told to re-pick.
                        val ctx = galleryPrefs.getString("in_progress_context", null)
                        galleryPrefs.edit()
                            .remove("in_progress_context")
                            .remove("in_progress_time")
                            .apply()
                        result.success(ctx)
                    }
                    "acknowledge" -> {
                        val path = call.argument<String>("path")
                        acknowledgeGalleryRecord(path)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Location-metadata consent extra for the system Photo Picker.
    // Defined as a literal so unknown pickers simply ignore it.
    private val extraLocationMetadata =
        "android.provider.extra.REQUEST_LOCATION_METADATA_ACCESS"
    private val actionPickImages = "android.provider.action.PICK_IMAGES"

    private fun handleGalleryPick(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        // Capability check: only where a Photo Picker activity actually
        // resolves — never assumed from the SDK level alone.
        val intent = Intent(actionPickImages).apply { type = "image/*" }
        if (packageManager.resolveActivity(intent, 0) == null) {
            result.success(mapOf("status" to "unsupported"))
            return
        }
        // An unacknowledged result must never be silently erased by a new
        // pick — return it instead of launching the picker.
        readPendingGalleryRecord()?.let { record ->
            result.success(record + ("status" to "pending"))
            return
        }
        if (pendingGalleryResult != null) {
            result.error("busy", "A gallery pick is already in progress", null)
            return
        }
        pendingGalleryResult = result
        pendingGalleryContext = call.argument<String>("context")
        galleryPrefs.edit()
            .putString("in_progress_context", pendingGalleryContext)
            .putLong("in_progress_time", System.currentTimeMillis())
            .apply()
        intent.putExtra(extraLocationMetadata, true)
        startActivityForResult(intent, requestGalleryPick)
    }

    private fun readPendingGalleryRecord(): HashMap<String, Any>? {
        val path = galleryPrefs.getString("result_path", null) ?: return null
        // A record whose staged temp file is already gone cannot be
        // recovered — clean it up rather than reporting a dead path.
        if (!File(path).exists()) {
            clearGalleryRecord()
            return null
        }
        return hashMapOf(
            "path" to path,
            "context" to (galleryPrefs.getString("result_context", "") ?: "")
        )
    }

    private fun clearGalleryRecord() {
        galleryPrefs.edit()
            .remove("result_path")
            .remove("result_context")
            .remove("result_time")
            .apply()
    }

    private fun acknowledgeGalleryRecord(path: String?) {
        val recorded = galleryPrefs.getString("result_path", null)
        if (recorded == null) return
        if (path != null && recorded != path) return
        clearGalleryRecord()
        // The photo has been staged into persistent storage — the temp
        // copy is disposable.
        File(recorded).delete()
    }

    private fun handleGalleryResult(resultCode: Int, data: Intent?) {
        val callback = pendingGalleryResult
        pendingGalleryResult = null
        val context = pendingGalleryContext
            ?: galleryPrefs.getString("in_progress_context", null)
        pendingGalleryContext = null
        galleryPrefs.edit().remove("in_progress_context")
            .remove("in_progress_time").apply()

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            callback?.success(mapOf("status" to "cancelled"))
            return
        }

        // Copy the default stream — with location consent granted the
        // picker's URI already carries full EXIF GPS.
        val path = try {
            val ext = contentResolver.getType(uri)
                ?.substringAfter('/')?.substringBefore(';')
                ?.let { if (it == "jpeg") "jpg" else it } ?: "jpg"
            val out = File(cacheDir, "gallery_pick_${System.currentTimeMillis()}.$ext")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(out).use { output -> input.copyTo(output) }
            } ?: throw IllegalStateException("Could not open selected photo")
            out.absolutePath
        } catch (e: Exception) {
            callback?.error("gallery_error", e.message, null)
            return
        }

        // Persist BEFORE notifying Dart — if the process dies between
        // delivery and staging, retrievePending can still recover it.
        galleryPrefs.edit()
            .putString("result_path", path)
            .putString("result_context", context ?: "")
            .putLong("result_time", System.currentTimeMillis())
            .apply()

        callback?.success(
            mapOf(
                "status" to "picked",
                "path" to path,
                "context" to (context ?: "")
            )
        )
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
        // The gallery result is handled even when the Dart callback is
        // gone (recreated activity after process death): the copy is
        // still written to the persistent record for later recovery.
        if (requestCode == requestGalleryPick) {
            handleGalleryResult(resultCode, data)
            return
        }
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
