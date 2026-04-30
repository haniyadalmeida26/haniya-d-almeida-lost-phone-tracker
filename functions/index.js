const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

exports.sendLostModeCommand = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'You must be signed in.');
  }

  const { deviceId, isLost, alarmActive } = request.data || {};
  if (!deviceId) {
    throw new HttpsError('invalid-argument', 'deviceId is required.');
  }

  const deviceRef = db.collection('devices').doc(deviceId);
  const deviceDoc = await deviceRef.get();

  if (!deviceDoc.exists) {
    throw new HttpsError('not-found', 'Device not found.');
  }

  const deviceData = deviceDoc.data() || {};
  if (deviceData.userId !== request.auth.uid) {
    throw new HttpsError(
      'permission-denied',
      'You do not own this device.',
    );
  }

  if (!deviceData.fcmToken) {
    throw new HttpsError(
      'failed-precondition',
      'Target phone has no FCM token yet. Open the app once on the phone first.',
    );
  }

  try {
    await messaging.send({
      token: deviceData.fcmToken,
      android: {
        priority: 'high',
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
          },
        },
      },
      data: {
        commandType: 'lost_mode_sync',
        deviceId,
        deviceName: deviceData.deviceName || 'Lost Phone',
        isLost: String(Boolean(isLost)),
        alarmActive: String(Boolean(alarmActive)),
        sentAt: new Date().toISOString(),
      },
    });

    await deviceRef.collection('events').add({
      type: 'cloud_function_push_sent',
      message: isLost
        ? 'Cloud Function sent Lost Mode wake-up push.'
        : 'Cloud Function sent Lost Mode clear push.',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      deviceId,
      isLost: Boolean(isLost),
      alarmActive: Boolean(alarmActive),
    };
  } catch (error) {
    logger.error('Failed to send Lost Mode command', error);
    throw new HttpsError('internal', error.message || 'Push send failed.');
  }
});
