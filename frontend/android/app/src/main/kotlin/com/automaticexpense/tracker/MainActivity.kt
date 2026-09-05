package com.automaticexpense.tracker

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val smsChannel = "com.automaticexpense.tracker/sms"
    private var methodChannel: MethodChannel? = null
    private var pendingSmsResult: MethodChannel.Result? = null
    private var pendingCaptureResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsChannel)
        SmsBroadcastReceiver.onCapturePersisted = {
            runOnUiThread {
                methodChannel?.invokeMethod("onSmsCaptured", null)
            }
        }
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSmsCaptureStatus" -> result.success(captureStatus())
                "requestSmsCaptureAuthorization" -> requestCaptureAuthorization(result)
                "getPendingSmsCaptureEvents" -> result.success(SmsCaptureStore(this).pendingEvents())
                "acknowledgeSmsCaptureEvent" -> {
                    val id = call.argument<String>("id")
                    if (id.isNullOrBlank()) result.error("INVALID_EVENT", "A capture event id is required", null)
                    else result.success(SmsCaptureStore(this).acknowledge(id))
                }
                "isSmsReceiverAvailable" -> result.success(true)
                "checkFinancialSender" -> result.success(
                    SmsBroadcastReceiver.isFinancialSender(call.argument<String>("sender"))
                )
                "readPast30DaysSms" -> {
                    if (checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED) {
                        fetchAndReturnPastSms(result)
                    } else {
                        pendingSmsResult = result
                        requestPermissions(arrayOf(Manifest.permission.READ_SMS), HISTORICAL_SMS_PERMISSION_REQUEST)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        SmsBroadcastReceiver.onCapturePersisted = null
        super.onDestroy()
    }

    private fun requestCaptureAuthorization(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED) {
            SmsCaptureStore(this).setCaptureEnabled(true)
            result.success(captureStatus())
            return
        }
        pendingCaptureResult = result
        requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), CAPTURE_SMS_PERMISSION_REQUEST)
    }

    private fun captureStatus(): Map<String, Boolean> {
        val granted = checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
        return mapOf(
            "supported" to true,
            "enabled" to SmsCaptureStore(this).isCaptureEnabled(),
            "hasReceivePermission" to granted,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            CAPTURE_SMS_PERMISSION_REQUEST -> {
                val result = pendingCaptureResult
                pendingCaptureResult = null
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                    SmsCaptureStore(this).setCaptureEnabled(true)
                }
                result?.success(captureStatus())
            }
            HISTORICAL_SMS_PERMISSION_REQUEST -> {
                val result = pendingSmsResult
                pendingSmsResult = null
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                    result?.let(::fetchAndReturnPastSms)
                } else {
                    result?.error("PERMISSION_DENIED", "User denied SMS reading permission", null)
                }
            }
        }
    }

    private fun fetchAndReturnPastSms(result: MethodChannel.Result) {
        try {
            val thirtyDaysAgo = System.currentTimeMillis() - (30L * 24 * 60 * 60 * 1000)
            val cursor = contentResolver.query(
                Uri.parse("content://sms/inbox"),
                arrayOf("address", "body", "date"),
                "date >= ?",
                arrayOf(thirtyDaysAgo.toString()),
                "date DESC",
            )
            val smsList = mutableListOf<Map<String, Any>>()
            cursor?.use {
                val addressIdx = it.getColumnIndex("address")
                val bodyIdx = it.getColumnIndex("body")
                val dateIdx = it.getColumnIndex("date")
                while (it.moveToNext()) {
                    val address = if (addressIdx >= 0) it.getString(addressIdx).orEmpty() else ""
                    val body = if (bodyIdx >= 0) it.getString(bodyIdx).orEmpty() else ""
                    if (SmsBroadcastReceiver.isFinancialSender(address) || SmsBroadcastReceiver.isFinancialBody(body)) {
                        smsList.add(mapOf(
                            "sender" to address,
                            "body" to body,
                            "timestamp" to if (dateIdx >= 0) it.getLong(dateIdx) else 0L,
                        ))
                    }
                }
            }
            result.success(smsList)
        } catch (error: Exception) {
            result.error("ERROR", error.message, null)
        }
    }

    companion object {
        private const val CAPTURE_SMS_PERMISSION_REQUEST = 201
        private const val HISTORICAL_SMS_PERMISSION_REQUEST = 202
    }
}
