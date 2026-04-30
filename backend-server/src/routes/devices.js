// ================================================================
// routes/devices.js — Device Registration + Lost Mode
// ================================================================

const express = require('express');
const router = express.Router();
const { db, messaging } = require('../services/firebaseService');
const { verifyToken, verifyFirebaseToken } = require('../middleware/auth');
const CryptoService = require('../services/cryptoService');

// ================================================================
// REGISTER DEVICE — POST /api/devices/register
// ================================================================
router.post('/register', verifyToken, async (req, res) => {
  try {
    const { deviceName, deviceModel, fcmToken } = req.body;
    const userId = req.user.userId;

    if (!deviceName || !deviceModel) {
      return res.status(400).json({
        error: 'deviceName and deviceModel are required'
      });
    }

    const deviceSecret = CryptoService.generateDeviceSecret();
    const currentBeaconId = CryptoService.getCurrentBeaconId(deviceSecret);

    const deviceRef = await db.collection('devices').add({
      userId,
      deviceName,
      deviceModel,
      fcmToken: fcmToken || null,
      deviceSecret,
      currentBeaconId,
      isLost: false,
      lostActivatedAt: null,
      lastSeenAt: null,
      lastSeenLocation: null,
      createdAt: new Date().toISOString()
    });

    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    const currentDevices = userDoc.data().devices || [];

    await userRef.update({
      devices: [...currentDevices, deviceRef.id]
    });

    res.status(201).json({
      message: '✅ Device registered successfully!',
      device: {
        deviceId: deviceRef.id,
        deviceName,
        deviceModel,
        deviceSecret,
        currentBeaconId,
        isLost: false
      }
    });

  } catch (error) {
    console.error('Register device error:', error);
    res.status(500).json({ error: 'Server error', details: error.message });
  }
});

// ================================================================
// ACTIVATE LOST MODE — POST /api/devices/lost
// ================================================================
router.post('/lost', verifyToken, async (req, res) => {
  try {
    const { deviceId } = req.body;
    const userId = req.user.userId;

    if (!deviceId) {
      return res.status(400).json({ error: 'deviceId is required' });
    }

    const deviceRef = db.collection('devices').doc(deviceId);
    const deviceDoc = await deviceRef.get();

    if (!deviceDoc.exists) {
      return res.status(404).json({ error: 'Device not found' });
    }

    if (deviceDoc.data().userId !== userId) {
      return res.status(403).json({ error: 'You do not own this device' });
    }

    if (deviceDoc.data().isLost) {
      return res.status(400).json({ error: 'Device is already in lost mode' });
    }

    await deviceRef.update({
      isLost: true,
      lostActivatedAt: new Date().toISOString()
    });

    res.json({
      message: '🚨 Lost mode activated!',
      deviceId,
      isLost: true,
      lostActivatedAt: new Date().toISOString()
    });

  } catch (error) {
    console.error('Lost mode error:', error);
    res.status(500).json({ error: 'Server error', details: error.message });
  }
});

router.post('/push-command', verifyFirebaseToken, async (req, res) => {
  try {
    const { deviceId, isLost, alarmActive } = req.body;
    const userId = req.user.uid;

    if (!deviceId) {
      return res.status(400).json({ error: 'deviceId is required' });
    }

    const deviceRef = db.collection('devices').doc(deviceId);
    const deviceDoc = await deviceRef.get();

    if (!deviceDoc.exists) {
      return res.status(404).json({ error: 'Device not found' });
    }

    const deviceData = deviceDoc.data();
    if (deviceData.userId !== userId) {
      return res.status(403).json({ error: 'You do not own this device' });
    }

    if (!deviceData.fcmToken) {
      return res.status(409).json({
        error: 'Target phone has no FCM token yet. Open the app once on the phone first.'
      });
    }

    await messaging.send({
      token: deviceData.fcmToken,
      android: {
        priority: 'high',
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true
          }
        }
      },
      data: {
        commandType: 'lost_mode_sync',
        deviceId,
        isLost: String(Boolean(isLost)),
        alarmActive: String(Boolean(alarmActive)),
        sentAt: new Date().toISOString()
      }
    });

    res.json({
      message: 'Push command sent successfully.',
      deviceId,
      isLost: Boolean(isLost),
      alarmActive: Boolean(alarmActive)
    });
  } catch (error) {
    console.error('Push command error:', error);
    res.status(500).json({ error: 'Server error', details: error.message });
  }
});

// ================================================================
// DEACTIVATE LOST MODE — POST /api/devices/found
// ================================================================
router.post('/found', verifyToken, async (req, res) => {
  try {
    const { deviceId } = req.body;
    const userId = req.user.userId;

    if (!deviceId) {
      return res.status(400).json({ error: 'deviceId is required' });
    }

    const deviceRef = db.collection('devices').doc(deviceId);
    const deviceDoc = await deviceRef.get();

    if (!deviceDoc.exists) {
      return res.status(404).json({ error: 'Device not found' });
    }

    if (deviceDoc.data().userId !== userId) {
      return res.status(403).json({ error: 'You do not own this device' });
    }

    await deviceRef.update({
      isLost: false,
      foundAt: new Date().toISOString()
    });

    res.json({
      message: '✅ Phone marked as found!',
      deviceId,
      isLost: false
    });

  } catch (error) {
    console.error('Found mode error:', error);
    res.status(500).json({ error: 'Server error', details: error.message });
  }
});

// ================================================================
// GET ALL MY DEVICES — GET /api/devices/mine
// ================================================================
router.get('/mine', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;

    const devicesQuery = await db.collection('devices')
      .where('userId', '==', userId)
      .get();

    const devices = devicesQuery.docs.map(doc => ({
      deviceId: doc.id,
      deviceName: doc.data().deviceName,
      deviceModel: doc.data().deviceModel,
      isLost: doc.data().isLost,
      lostActivatedAt: doc.data().lostActivatedAt,
      lastSeenAt: doc.data().lastSeenAt,
      lastSeenLocation: doc.data().lastSeenLocation,
      createdAt: doc.data().createdAt
    }));

    res.json({
      message: '✅ Devices fetched!',
      count: devices.length,
      devices
    });

  } catch (error) {
    console.error('Get devices error:', error);
    res.status(500).json({ error: 'Server error', details: error.message });
  }
});

// Test route
router.get('/test', (req, res) => {
  res.json({ message: '✅ Devices route working!' });
});

module.exports = router;
