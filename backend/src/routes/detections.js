// ================================================================
// routes/detections.js — Detection Reporting
// ================================================================

const express = require('express');
const router = express.Router();
const { db } = require('../services/firebaseService');
const CryptoService = require('../services/cryptoService');

// ================================================================
// REPORT A DETECTION — POST /api/detections/report
// ================================================================
router.post('/report', async (req, res) => {
  try {
    const { beaconId, latitude, longitude, accuracy, scoutId } = req.body;

    if (!beaconId || !latitude || !longitude) {
      return res.status(400).json({
        error: 'beaconId, latitude, and longitude are required'
      });
    }

    const lostDevicesQuery = await db.collection('devices')
      .where('isLost', '==', true)
      .get();

    if (lostDevicesQuery.empty) {
      return res.json({ message: 'No lost devices to match' });
    }

    const lostDevices = lostDevicesQuery.docs.map(doc => ({
      deviceId: doc.id,
      deviceSecret: doc.data().deviceSecret
    }));

    const matchedDeviceId = CryptoService.identifyDevice(
      beaconId,
      lostDevices
    );

    if (!matchedDeviceId) {
      return res.json({ message: 'Beacon not matched to any lost device' });
    }

    const detectionData = {
      deviceId: matchedDeviceId,
      beaconId,
      latitude,
      longitude,
      accuracy: accuracy || null,
      scoutId: scoutId || 'anonymous',
      detectedAt: new Date().toISOString()
    };

    const detectionRef = await db.collection('detections').add(detectionData);

    await db.collection('devices').doc(matchedDeviceId).update({
      lastSeenAt: new Date().toISOString(),
      lastSeenLocation: { latitude, longitude }
    });

    const deviceDoc = await db.collection('devices')
      .doc(matchedDeviceId).get();
    const ownerId = deviceDoc.data().userId;

    const activeOwners = req.app.get('activeOwners');
    const ownerSocket = activeOwners.get(ownerId);

    if (ownerSocket) {
      ownerSocket.send(JSON.stringify({
        type: 'new_detection',
        detection: {
          detectionId: detectionRef.id,
          deviceId: matchedDeviceId,
          latitude,
          longitude,
          accuracy,
          detectedAt: detectionData.detectedAt
        }
      }));
      console.log(`📍 Real-time update sent to owner ${ownerId}`);
    }

    res.status(201).json({
      message: '✅ Detection reported!',
      detectionId: detectionRef.id,
      matchedDevice: matchedDeviceId,
      location: { latitude, longitude }
    });

  } catch (error) {
    console.error('Detection error:', error);
    res.status(500).json({ error: 'Server error', details: error.message });
  }
});

// ================================================================
// GET DETECTION HISTORY — GET /api/detections/history/:deviceId
// ================================================================
router.get('/history/:deviceId', async (req, res) => {
  try {
    const { deviceId } = req.params;

    const detectionsQuery = await db.collection('detections')
      .where('deviceId', '==', deviceId)
      .orderBy('detectedAt', 'desc')
      .limit(50)
      .get();

    const detections = detectionsQuery.docs.map(doc => ({
      detectionId: doc.id,
      latitude: doc.data().latitude,
      longitude: doc.data().longitude,
      accuracy: doc.data().accuracy,
      detectedAt: doc.data().detectedAt
    }));

    res.json({
      message: '✅ History fetched!',
      deviceId,
      count: detections.length,
      detections
    });

  } catch (error) {
    console.error('History error:', error);
    res.status(500).json({ error: 'Server error', details: error.message });
  }
});

// Test route
router.get('/test', (req, res) => {
  res.json({ message: '✅ Detections route working!' });
});

module.exports = router;
