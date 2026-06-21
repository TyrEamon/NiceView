package com.ortlinde.nice_view

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val downloadChannelName = "nice_view/downloads"
    private val backupChannelName = "nice_view/backups"
    private val createBackupRequestCode = 7101
    private val openBackupRequestCode = 7102
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingBackupBytes: ByteArray? = null
    private var pendingBackupFileName: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        try {
                            val bytes = call.argument<ByteArray>("bytes")
                                ?: throw IllegalArgumentException("bytes is required")
                            val fileName = call.argument<String>("fileName")
                                ?: "nice_view_${System.currentTimeMillis()}.jpg"
                            val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
                            val relativeSubDir = call.argument<String>("relativeSubDir")
                            result.success(saveImage(bytes, fileName, mimeType, relativeSubDir))
                        } catch (error: Throwable) {
                            result.error("SAVE_IMAGE_FAILED", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exportJson" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName")
                            ?: "niceview-backup.json"
                        if (bytes == null) {
                            result.error("EXPORT_BACKUP_FAILED", "bytes is required", null)
                            return@setMethodCallHandler
                        }
                        startCreateBackupDocument(bytes, fileName, result)
                    }
                    "importJson" -> startOpenBackupDocument(result)
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            createBackupRequestCode -> finishCreateBackupDocument(resultCode, data?.data)
            openBackupRequestCode -> finishOpenBackupDocument(resultCode, data?.data)
        }
    }

    private fun saveImage(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        relativeSubDir: String?
    ): String {
        val resolver = applicationContext.contentResolver
        val relativePath = buildPicturesRelativePath(relativeSubDir)
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    relativePath
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Unable to create image entry")

        resolver.openOutputStream(uri)?.use { stream ->
            stream.write(bytes)
            stream.flush()
        } ?: throw IllegalStateException("Unable to open image output stream")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val completed = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            resolver.update(uri, completed, null, null)
        }
        return uri.toString()
    }

    private fun buildPicturesRelativePath(relativeSubDir: String?): String {
        val root = Environment.DIRECTORY_PICTURES + "/NiceView"
        val subDir = relativeSubDir?.trim()?.trim('/')
        if (subDir.isNullOrEmpty()) {
            return root
        }
        return "$root/$subDir"
    }

    private fun startCreateBackupDocument(
        bytes: ByteArray,
        fileName: String,
        result: MethodChannel.Result
    ) {
        if (pendingBackupResult != null) {
            result.error("BACKUP_BUSY", "已有备份操作正在进行", null)
            return
        }
        pendingBackupResult = result
        pendingBackupBytes = bytes
        pendingBackupFileName = fileName
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            startActivityForResult(intent, createBackupRequestCode)
        } catch (error: Throwable) {
            clearPendingBackup()
            result.error("EXPORT_BACKUP_FAILED", error.message, null)
        }
    }

    private fun startOpenBackupDocument(result: MethodChannel.Result) {
        if (pendingBackupResult != null) {
            result.error("BACKUP_BUSY", "已有备份操作正在进行", null)
            return
        }
        pendingBackupResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
            }
            startActivityForResult(intent, openBackupRequestCode)
        } catch (error: Throwable) {
            clearPendingBackup()
            result.error("IMPORT_BACKUP_FAILED", error.message, null)
        }
    }

    private fun finishCreateBackupDocument(resultCode: Int, uri: Uri?) {
        val result = pendingBackupResult ?: return
        val bytes = pendingBackupBytes
        val fileName = pendingBackupFileName ?: "niceview-backup.json"
        clearPendingBackup()
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) {
            result.error("EXPORT_BACKUP_CANCELLED", "已取消导出", null)
            return
        }
        try {
            contentResolver.openOutputStream(uri, "wt")?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IllegalStateException("Unable to open backup output stream")
            result.success(uri.toString().ifEmpty { fileName })
        } catch (error: Throwable) {
            result.error("EXPORT_BACKUP_FAILED", error.message, null)
        }
    }

    private fun finishOpenBackupDocument(resultCode: Int, uri: Uri?) {
        val result = pendingBackupResult ?: return
        clearPendingBackup()
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.error("IMPORT_BACKUP_CANCELLED", "已取消导入", null)
            return
        }
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { stream ->
                stream.readBytes()
            } ?: throw IllegalStateException("Unable to open backup input stream")
            result.success(bytes)
        } catch (error: Throwable) {
            result.error("IMPORT_BACKUP_FAILED", error.message, null)
        }
    }

    private fun clearPendingBackup() {
        pendingBackupResult = null
        pendingBackupBytes = null
        pendingBackupFileName = null
    }
}
