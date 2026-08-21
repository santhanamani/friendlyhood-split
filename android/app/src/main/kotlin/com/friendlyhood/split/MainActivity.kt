package com.friendlyhood.split

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "com.friendlyhood.split/app_update"
        private const val UPI_CHANNEL = "com.friendlyhood.split/upi_payment"
        private const val UPI_REQUEST_CODE = 4817
    }

    private var pendingUpiResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                        result.success(allowed)
                    }
                    "openInstallPermissionSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    "launchInstaller" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "The downloaded APK path is missing.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            launchInstaller(File(path))
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("INSTALLER_FAILED", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPI_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "pay") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingUpiResult != null) {
                    result.error("PAYMENT_IN_PROGRESS", "Another UPI payment is already open.", null)
                    return@setMethodCallHandler
                }
                val payeeUpiId = call.argument<String>("payeeUpiId").orEmpty()
                val payeeName = call.argument<String>("payeeName").orEmpty()
                val amount = call.argument<String>("amount").orEmpty()
                val reference = call.argument<String>("transactionReference").orEmpty()
                val description = call.argument<String>("description").orEmpty()
                if (payeeUpiId.isBlank() || amount.isBlank() || reference.isBlank()) {
                    result.error("INVALID_PAYMENT", "UPI ID, amount and reference are required.", null)
                    return@setMethodCallHandler
                }
                val uri = Uri.Builder()
                    .scheme("upi")
                    .authority("pay")
                    .appendQueryParameter("pa", payeeUpiId)
                    .appendQueryParameter("pn", payeeName)
                    .appendQueryParameter("tr", reference)
                    .appendQueryParameter("tn", description)
                    .appendQueryParameter("am", amount)
                    .appendQueryParameter("cu", "INR")
                    .build()
                val paymentIntent = Intent(Intent.ACTION_VIEW, uri)
                val chooser = Intent.createChooser(paymentIntent, "Pay with UPI")
                if (paymentIntent.resolveActivity(packageManager) == null) {
                    result.error("NO_UPI_APP", "No UPI payment app is installed.", null)
                    return@setMethodCallHandler
                }
                pendingUpiResult = result
                startActivityForResult(chooser, UPI_REQUEST_CODE)
            }
    }

    @Deprecated("Deprecated in Android SDK, retained for UPI intent compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != UPI_REQUEST_CODE) return
        val result = pendingUpiResult ?: return
        pendingUpiResult = null
        val raw = data?.getStringExtra("response")
            ?: data?.dataString
            ?: ""
        if (raw.isBlank() && resultCode != RESULT_OK) {
            result.success(mapOf("status" to "cancelled"))
            return
        }
        val values = raw.split("&")
            .mapNotNull { part ->
                val pieces = part.split("=", limit = 2)
                if (pieces.size == 2) pieces[0].lowercase() to pieces[1] else null
            }
            .toMap()
        val status = when (values["status"]?.lowercase()) {
            "success" -> "success"
            "submitted" -> "submitted"
            "failure", "failed" -> "failed"
            else -> if (values["responsecode"] == "00") "submitted" else "unknown"
        }
        result.success(mapOf(
            "status" to status,
            "reference" to (values["txnref"] ?: values["tr"].orEmpty()),
            "transactionId" to (values["txnid"] ?: values["approvalrefno"].orEmpty()),
            "responseCode" to values["responsecode"].orEmpty(),
        ))
    }

    private fun launchInstaller(apk: File) {
        require(apk.exists() && apk.isFile) { "The downloaded APK does not exist." }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
