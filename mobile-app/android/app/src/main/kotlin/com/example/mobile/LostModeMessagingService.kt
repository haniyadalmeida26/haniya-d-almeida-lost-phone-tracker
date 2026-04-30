package com.example.mobile

import android.content.Intent
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class LostModeMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val data = message.data
        if (data["commandType"] != "lost_mode_sync") {
            return
        }

        val isLost = data["isLost"] == "true"
        val alarmActive = data["alarmActive"] == "true"
        val serviceIntent = Intent(this, LostModeForegroundService::class.java).apply {
            action = if (isLost || alarmActive) {
                LostModeForegroundService.ACTION_START
            } else {
                LostModeForegroundService.ACTION_STOP
            }
            putExtra(LostModeForegroundService.EXTRA_DEVICE_ID, data["deviceId"] ?: "")
            putExtra(
                LostModeForegroundService.EXTRA_DEVICE_NAME,
                data["deviceName"] ?: "Lost Phone",
            )
            putExtra(LostModeForegroundService.EXTRA_ALARM_ACTIVE, alarmActive)
            putExtra(LostModeForegroundService.EXTRA_OPEN_UI, isLost)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }
}
