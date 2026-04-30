// ================================================================
// routes/auth.js — Register & Login
// ================================================================

const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { db } = require('../services/firebaseService');

// Helper — creates a login token for a user
const createToken = (userId, email) => {
  return jwt.sign(
    { userId, email },
    process.env.JWT_SECRET,
    { expiresIn: '30d' }
  );
};

// ── REGISTER ─────────────────────────────────────────────────────
// POST /api/auth/register
// Body: { "email": "a@b.com", "password": "123456", "name": "John" }
router.post('/register', async (req, res) => {
  try {
    const { email, password, name } = req.body;

    // Validate inputs
    if (!email || !password || !name) {
      return res.status(400).json({
        error: 'All fields required: email, password, name'
      });
    }
    if (password.length < 6) {
      return res.status(400).json({
        error: 'Password must be at least 6 characters'
      });
    }

    // Check if email already exists
    const existing = await db.collection('users')
      .where('email', '==', email).get();

    if (!existing.empty) {
      return res.status(409).json({
        error: 'An account with this email already exists'
      });
    }

    // Hash the password — NEVER store plain text passwords
    const hashedPassword = await bcrypt.hash(password, 10);

    // Save user to Firestore database
    const userRef = await db.collection('users').add({
      email,
      name,
      password: hashedPassword,
      createdAt: new Date().toISOString(),
      devices: []
    });

    // Create token and send response
    const token = createToken(userRef.id, email);

    res.status(201).json({
      message: '✅ Account created successfully!',
      token,
      user: { userId: userRef.id, email, name }
    });

  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Server error', details: error.message });
  }
});

// ── LOGIN ─────────────────────────────────────────────────────────
// POST /api/auth/login
// Body: { "email": "a@b.com", "password": "123456" }
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        error: 'Email and password are required'
      });
    }

    // Find user by email
    const userQuery = await db.collection('users')
      .where('email', '==', email).get();

    if (userQuery.empty) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    const userDoc = userQuery.docs[0];
    const userData = userDoc.data();

    // Check password against stored hash
    const passwordMatch = await bcrypt.compare(password, userData.password);

    if (!passwordMatch) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    // Create token and send response
    const token = createToken(userDoc.id, email);

    res.json({
      message: '✅ Login successful!',
      token,
      user: {
        userId: userDoc.id,
        email: userData.email,
        name: userData.name,
        devices: userData.devices || []
      }
    });

  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Server error', details: error.message });
  }
});

// Test route
router.get('/test', (req, res) => {
  res.json({ message: '✅ Auth route working!' });
});

module.exports = router;

