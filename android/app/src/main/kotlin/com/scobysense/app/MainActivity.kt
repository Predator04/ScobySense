package com.scobysense.app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val channelName = "scobysense/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("BAD_ARG", "path missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            launchInstall(path, result)
                        } catch (e: Throwable) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchInstall(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("INSTALL_FAILED", "APK not found at $path", null)
            return
        }

        if (!packageManager.canRequestPackageInstalls()) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (_: Throwable) {
                // fall through; the error below is what the UI reacts to
            }
            result.error(
                "NEEDS_INSTALL_PERMISSION",
                "Allow installs from ScobySense in system settings, then retry.",
                null,
            )
            return
        }

        if (!signatureMatches(file)) {
            result.error(
                "SIGNATURE_MISMATCH",
                "Downloaded APK is not signed with the same certificate as the installed app. Refusing to install.",
                null,
            )
            return
        }

        val authority = "$packageName.fileprovider"
        val uri: Uri = FileProvider.getUriForFile(this, authority, file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
        result.success(null)
    }

    @Suppress("DEPRECATION")
    private fun signatureMatches(apk: File): Boolean {
        return try {
            val installedDigests = runningAppSigningDigests() ?: return false
            val apkDigests = apkSigningDigests(apk.absolutePath) ?: return false
            // Any shared signer counts as a match (rotation / multi-signer).
            installedDigests.any { apkDigests.contains(it) }
        } catch (_: Throwable) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun runningAppSigningDigests(): Set<String>? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
            val sigInfo = info.signingInfo ?: return null
            val sigs = if (sigInfo.hasMultipleSigners()) {
                sigInfo.apkContentsSigners
            } else {
                sigInfo.signingCertificateHistory
            }
            sigs?.map { sha256Hex(it.toByteArray()) }?.toSet()
        } else {
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            info.signatures?.map { sha256Hex(it.toByteArray()) }?.toSet()
        }
    }

    @Suppress("DEPRECATION")
    private fun apkSigningDigests(path: String): Set<String>? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = packageManager.getPackageArchiveInfo(
                path,
                PackageManager.GET_SIGNING_CERTIFICATES,
            ) ?: return null
            val sigInfo = info.signingInfo ?: return null
            val sigs = if (sigInfo.hasMultipleSigners()) {
                sigInfo.apkContentsSigners
            } else {
                sigInfo.signingCertificateHistory
            }
            sigs?.map { sha256Hex(it.toByteArray()) }?.toSet()
        } else {
            val info = packageManager.getPackageArchiveInfo(path, PackageManager.GET_SIGNATURES)
                ?: return null
            info.signatures?.map { sha256Hex(it.toByteArray()) }?.toSet()
        }
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val d = MessageDigest.getInstance("SHA-256").digest(bytes)
        val sb = StringBuilder(d.size * 2)
        for (b in d) {
            val v = b.toInt() and 0xff
            sb.append(HEX[v ushr 4])
            sb.append(HEX[v and 0x0f])
        }
        return sb.toString()
    }

    companion object {
        private val HEX = "0123456789abcdef".toCharArray()
    }
}
