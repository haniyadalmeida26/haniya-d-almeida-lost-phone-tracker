// ================================================================
// firebaseService.js — Connects Your Server To Firebase
// ================================================================
// Think of this file as the phone line between your 
// Node.js server and your Firebase database.
// Every other file imports from here when it needs the database.
// ================================================================

const admin = require('firebase-admin');
const path = require('path');

// Load the secret key file you downloaded from Firebase
const serviceAccount = require(
  path.join(__dirname, '../../serviceAccountKey.json')
);

// Connect to Firebase — the "if" check stops errors if this
// file gets imported by multiple files at the same time
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: `${process.env.FIREBASE_PROJECT_ID}.appspot.com`
  });
  console.log('✅ Firebase connected successfully');
}

// These are the 4 Firebase tools other files will use:
const db        = admin.firestore();   // Database — store/read data
const auth      = admin.auth();        // Authentication — manage users
const storage   = admin.storage();     // Storage — save photos
const messaging = admin.messaging();   // Push notifications — alert owner

module.exports = { db, auth, storage, messaging, admin };