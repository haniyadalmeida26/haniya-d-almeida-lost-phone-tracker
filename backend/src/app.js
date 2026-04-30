const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const http = require('http');
const { WebSocketServer } = require('ws');
require('dotenv').config();

const app = express();
const server = http.createServer(app);

app.use(helmet());
app.use(cors());
app.use(morgan('dev'));
app.use(express.json());

const wss = new WebSocketServer({ server });
const activeOwners = new Map();

wss.on('connection', (ws, req) => {
  const params = new URLSearchParams(req.url.replace('/?', ''));
  const userId = params.get('userId');
  if (userId) {
    activeOwners.set(userId, ws);
    console.log(`👁️  Owner ${userId} is now watching live`);
    ws.send(JSON.stringify({ type: 'connected', message: 'Live tracking active' }));
  }
  ws.on('close', () => {
    activeOwners.delete(userId);
  });
});

app.set('activeOwners', activeOwners);

app.use('/api/auth',       require('./routes/auth'));
app.use('/api/devices',    require('./routes/devices'));
app.use('/api/detections', require('./routes/detections'));

app.get('/health', (req, res) => {
  res.json({
    status: '✅ online',
    project: 'Lost Phone Tracker',
    timestamp: new Date().toISOString(),
    endpoints: ['/api/auth', '/api/devices', '/api/detections']
  });
});

app.use((req, res) => {
  res.status(404).json({ error: 'Route not found', tried: req.originalUrl });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`
  ==========================================
  🚀  Server running at http://localhost:${PORT}
  📡  WebSocket ready for live tracking
  🔒  Security middleware active
  ==========================================
  `);
});