package com.example.mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions

class LostModeForegroundService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private var locationCallback: LocationCallback? = null
    private var currentDeviceId: String? = null
    private var currentAlarmActive: Boolean = false

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        if (action == ACTION_STOP) {
            stopLocationTracking()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        createNotificationChannel()

        val deviceId = intent?.getStringExtra(EXTRA_DEVICE_ID)
        val deviceName = intent?.getStringExtra(EXTRA_DEVICE_NAME) ?: "Lost Phone"
        val alarmActive = intent?.getBooleanExtra(EXTRA_ALARM_ACTIVE, false) ?: false
        val shouldOpenUi = intent?.getBooleanExtra(EXTRA_OPEN_UI, false) ?: false
        currentAlarmActive = alarmActive

        startForeground(NOTIFICATION_ID, buildNotification(deviceName, alarmActive))
        setAlarmPlayback(alarmActive)
        if (!deviceId.isNullOrEmpty()) {
            startLocationTracking(deviceId)
        }

        if (shouldOpenUi) {
            val launchIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("open_lost_mode", true)
            }
            startActivity(launchIntent)
        }

        return START_STICKY
    }

    override fun onDestroy() {
        stopLocationTracking()
        stopAlarmPlayback()
        super.onDestroy()
    }

    private fun buildNotification(deviceName: String, alarmActive: Boolean): Notification {
        val launchIntent = Intent(this, MainActivity::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentIntent = PendingIntent.getActivity(this, 0, launchIntent, flags)

        val text = if (alarmActive) {
            "$deviceName is in Lost Mode. Alarm is active."
        } else {
            "$deviceName is in Lost Mode. Tracking is active."
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Lost Mode Active")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .setFullScreenIntent(contentIntent, alarmActive)
            .build()
    }

    private fun setAlarmPlayback(enabled: Boolean) {
        if (enabled) {
            if (mediaPlayer?.isPlaying == true) {
                return
            }

            try {
                val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                mediaPlayer = MediaPlayer().apply {
                    setDataSource(applicationContext, alarmUri)
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    isLooping = true
                    prepare()
                    start()
                }
            } catch (_: Exception) {
            }
        } else {
            stopAlarmPlayback()
        }
    }

    private fun stopAlarmPlayback() {
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
    }

    private fun startLocationTracking(deviceId: String) {
        if (!hasLocationPermission()) {
            return
        }

        if (currentDeviceId == deviceId && locationCallback != null) {
            return
        }

        stopLocationTracking()
        currentDeviceId = deviceId

        val request = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            LOCATION_INTERVAL_MS,
        )
            .setMinUpdateIntervalMillis(LOCATION_INTERVAL_MS)
            .setWaitForAccurateLocation(false)
            .build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val location = result.lastLocation ?: return
                publishLocation(deviceId, location)
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(
                request,
                locationCallback as LocationCallback,
                Looper.getMainLooper(),
            )
            fusedLocationClient.lastLocation.addOnSuccessListener { location ->
                if (location != null) {
                    publishLocation(deviceId, location)
                }
            }
        } catch (_: SecurityException) {
        }
    }

    private fun stopLocationTracking() {
        locationCallback?.let { callback ->
            fusedLocationClient.removeLocationUpdates(callback)
        }
        locationCallback = null
        currentDeviceId = null
    }

    private fun publishLocation(deviceId: String, location: Location) {
        val user = FirebaseAuth.getInstance().currentUser ?: return
        val db = FirebaseFirestore.getInstance()
        val recordedAt = Timestamp.now()

        val lastLocation = hashMapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracy" to location.accuracy.toDouble(),
            "source" to "native_foreground_service",
            "recordedAt" to recordedAt,
        )

        db.collection("devices").document(deviceId).set(
            hashMapOf(
                "userId" to user.uid,
                "lastHeartbeatAt" to FieldValue.serverTimestamp(),
                "lastLocation" to lastLocation,
                "status" to hashMapOf(
                    "isLost" to true,
                    "isOnline" to true,
                    "possibleSwitchOff" to false,
                    "offlineReason" to null,
                    "alarmActive" to currentAlarmActive,
                ),
                "nativeService" to hashMapOf(
                    "active" to true,
                    "lastUpdateAt" to FieldValue.serverTimestamp(),
                ),
            ),
            SetOptions.merge(),
        )

        db.collection("devices").document(deviceId).collection("location_history").add(
            hashMapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "accuracy" to location.accuracy.toDouble(),
                "source" to "native_foreground_service",
                "recordedAt" to recordedAt,
                "timestamp" to FieldValue.serverTimestamp(),
            ),
        )
    }

    private fun hasLocationPermission(): Boolean {
        val fineLocationGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarseLocationGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return fineLocationGranted || coarseLocationGranted
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Lost Mode Service",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Keeps Lost Mode tracking alive in the background"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "lost_mode_service_channel"
        private const val NOTIFICATION_ID = 246701
        private const val LOCATION_INTERVAL_MS = 5000L

        const val ACTION_START = "com.example.mobile.LOST_MODE_START"
        const val ACTION_STOP = "com.example.mobile.LOST_MODE_STOP"
        const val EXTRA_DEVICE_ID = "device_id"
        const val EXTRA_DEVICE_NAME = "device_name"
        const val EXTRA_ALARM_ACTIVE = "alarm_active"
        const val EXTRA_OPEN_UI = "open_ui"
    }
}
