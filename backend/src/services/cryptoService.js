// ================================================================
// cryptoService.js — The Rotating ID Privacy Engine
// ================================================================
// Your lost phone broadcasts a Bluetooth ID that changes
// every 15 minutes. Nobody can track you — but YOUR server
// can always figure out which phone was detected.
// ================================================================

const crypto = require('crypto');

class CryptoService {

  static TIME_WINDOW_MINUTES = 15;

  // Get the ID the lost phone should broadcast RIGHT NOW
  static getCurrentBeaconId(deviceSecret) {
    const currentWindow = this.getCurrentTimeWindow();
    return this.buildBeaconId(deviceSecret, currentWindow);
  }

  // When a detection arrives, figure out WHICH phone it is
  // by trying all registered lost phones
  static identifyDevice(detectedId, lostDevices) {
    const windowsToCheck = this.getRecentWindows(4);

    for (const device of lostDevices) {
      for (const window of windowsToCheck) {
        const expectedId = this.buildBeaconId(device.deviceSecret, window);
        if (expectedId === detectedId) {
          return device.deviceId; // ✅ Found the match!
        }
      }
    }
    return null; // Unknown device
  }

  // Generate a brand new random secret for a new device
  static generateDeviceSecret() {
    return crypto.randomBytes(32).toString('hex');
  }

  // ── Private helpers ─────────────────────────────────────────
  static getCurrentTimeWindow() {
    return Math.floor(
      Date.now() / (this.TIME_WINDOW_MINUTES * 60 * 1000)
    );
  }

  static getRecentWindows(count) {
    const current = this.getCurrentTimeWindow();
    return Array.from({ length: count }, (_, i) => current - i);
  }

  static buildBeaconId(secret, window) {
    return crypto
      .createHmac('sha256', secret)
      .update(window.toString())
      .digest('hex')
      .substring(0, 16);
  }
}

module.exports = CryptoService;