# Lost Phone Tracker Implementation Guide

## Step 1. Device ID system
- Each installed app instance generates or reuses a stable `deviceId`.
- The current implementation stores it locally with `SharedPreferences`.
- The same account can sign in on multiple devices and control any registered `deviceId`.

## Step 2. Firestore structure

### `users/{userId}`
```json
{
  "email": "owner@example.com",
  "name": "owner",
  "devices": ["device_1", "device_2"],
  "createdAt": "serverTimestamp"
}
```

### `devices/{deviceId}`
```json
{
  "deviceId": "device_1",
  "userId": "ownerUid",
  "deviceName": "Samsung M14",
  "model": "Samsung M14",
  "platform": "android",
  "osVersion": "14",
  "registeredAt": "serverTimestamp",
  "lastHeartbeatAt": "serverTimestamp",
  "lastLocation": {
    "latitude": 12.9716,
    "longitude": 77.5946,
    "accuracy": 10.2,
    "source": "heartbeat",
    "recordedAt": "timestamp"
  },
  "latestDetection": {
    "latitude": 12.9720,
    "longitude": 77.5950,
    "finderLabel": "simulated-finder",
    "timestamp": "timestamp"
  },
  "prediction": {
    "latitude": 12.9730,
    "longitude": 77.5960,
    "confidence": 0.55,
    "generatedAt": "serverTimestamp"
  },
  "status": {
    "isLost": true,
    "isOnline": false,
    "possibleSwitchOff": true,
    "offlineReason": "possible_switch_off_or_network_loss",
    "lostActivatedAt": "serverTimestamp",
    "lastDetectionAt": "serverTimestamp"
  }
}
```

### `devices/{deviceId}/location_history/{entryId}`
```json
{
  "latitude": 12.9716,
  "longitude": 77.5946,
  "accuracy": 10.2,
  "source": "heartbeat",
  "recordedAt": "timestamp",
  "timestamp": "serverTimestamp"
}
```

### `devices/{deviceId}/detections/{detectionId}`
```json
{
  "deviceId": "device_1",
  "ownerUserId": "ownerUid",
  "finderUserId": "finderUid",
  "finderDeviceId": "device_2",
  "finderLabel": "simulated-finder",
  "source": "simulation",
  "latitude": 12.9720,
  "longitude": 77.5950,
  "accuracy": 8.0,
  "timestamp": "timestamp",
  "createdAt": "serverTimestamp"
}
```

## Step 3. Controller device marks phone as LOST
- Sign into the same account on another phone or laptop build.
- Select the target device from the device list.
- Press `Mark Lost`.
- Firestore updates `devices/{deviceId}.status.isLost = true`.

## Step 4. Lost phone listens to LOST status
- The missing phone listens to its own `devices/{currentDeviceId}` document.
- When `status.isLost` becomes `true`, it stays in Lost Mode logic and keeps sending location heartbeats.

## Step 5. Finder device detection logic
- First stage: simulated detection.
- Another logged-in device presses `Simulate Finder Detection`.
- Later, real Bluetooth detection can write to the same `devices/{deviceId}/detections` path.

## Step 6. Upload detection data to Firebase
- Finder writes a detection document into `devices/{lostDeviceId}/detections`.
- The target device document also stores `latestDetection` for quick UI reads.

## Step 7. Show detection points and last seen on map
- Blue marker: last known GPS from the lost phone.
- Red markers: finder detections.
- Orange marker: predicted next location.

## Step 8. Offline detection logic
- If `lastHeartbeatAt` is older than 2 minutes, device is marked offline.
- If the last two movement points show motion before silence, set:
  - `possibleSwitchOff = true`
  - `offlineReason = possible_switch_off_or_network_loss`

## Step 9. Simple AI prediction logic
- Read last 2-3 location points.
- Compute average movement delta.
- Project one step forward.
- Save result to `devices/{deviceId}.prediction`.

## Step 10. Testing setup

### One phone + laptop
1. Run the Flutter app on the phone.
2. Run the Flutter app on Windows/web as controller if your Firebase config supports it.
3. Sign into the same account on both.
4. On laptop/controller, select the phone and mark it lost.
5. Press `Simulate Finder Detection`.
6. Open map and history to confirm points.

### Two phones
1. Install the app on both phones.
2. Sign into the same owner account on both.
3. Phone A is the lost device.
4. Phone B is the controller/finder simulator.
5. Mark Phone A as lost from Phone B.
6. Simulate finder detection from Phone B.
7. Confirm offline behavior by closing or disconnecting Phone A and waiting past threshold.

## Important real-world limitation
- If the phone is physically switched off, it cannot send GPS, Bluetooth beacons, or network updates.
- That is why the system must rely on:
  - last known location
  - last finder detection
  - offline status
  - sudden disconnect hint
  - prediction from previous movement

## Next upgrade after simulation
- Replace `Simulate Finder Detection` with Bluetooth scan results.
- Keep the Firestore write path unchanged so UI and analytics continue to work.
