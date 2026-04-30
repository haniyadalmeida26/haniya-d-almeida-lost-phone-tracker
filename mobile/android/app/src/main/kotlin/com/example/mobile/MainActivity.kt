package com.example.mobile

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val channelName = "lost_phone_tracker/background"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLostModeService" -> {
                    val deviceId = call.argument<String>("deviceId") ?: ""
                    val deviceName = call.argument<String>("deviceName") ?: "Lost Phone"
                    val alarmActive = call.argument<Boolean>("alarmActive") ?: false
                    val openUi = call.argument<Boolean>("openUi") ?: false
                    startLostModeService(deviceId, deviceName, alarmActive, openUi)
                    result.success(null)
                }

                "stopLostModeService" -> {
                    stopLostModeService()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun startLostModeService(
        deviceId: String,
        deviceName: String,
        alarmActive: Boolean,
        openUi: Boolean,
    ) {
        val intent = Intent(this, LostModeForegroundService::class.java).apply {
            action = LostModeForegroundService.ACTION_START
            putExtra(LostModeForegroundService.EXTRA_DEVICE_ID, deviceId)
            putExtra(LostModeForegroundService.EXTRA_DEVICE_NAME, deviceName)
            putExtra(LostModeForegroundService.EXTRA_ALARM_ACTIVE, alarmActive)
            putExtra(LostModeForegroundService.EXTRA_OPEN_UI, openUi)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopLostModeService() {
        val intent = Intent(this, LostModeForegroundService::class.java).apply {
            action = LostModeForegroundService.ACTION_STOP
        }
        startService(intent)
    }
}
