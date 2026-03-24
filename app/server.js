const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
const version = process.env.VERSION || 'unknown';
const color = process.env.COLOR || 'unknown';

// Root endpoint - shows version info
app.get('/', (req, res) => {
  res.json({
    application: 'Blue-Green Demo',
    version: version,
    color: color,
    timestamp: new Date().toISOString(),
    hostname: require('os').hostname()
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    version: version,
    color: color
  });
});

// Readiness probe endpoint
app.get('/ready', (req, res) => {
  res.status(200).json({
    status: 'ready',
    version: version
  });
});

// Version endpoint
app.get('/version', (req, res) => {
  res.json({
    version: version,
    color: color
  });
});

// Start server
app.listen(port, () => {
  console.log(`Blue-Green Demo App v${version} (${color}) listening on port ${port}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    console.log('HTTP server closed');
  });
});
