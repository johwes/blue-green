const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
const version = process.env.VERSION || 'unknown';
const color = process.env.COLOR || 'unknown';

// Configuration from ConfigMap
const config = {
  maxRequestsPerMinute: parseInt(process.env.MAX_REQUESTS_PER_MINUTE || '100'),
  featureFlags: {
    enableNewUI: process.env.FEATURE_NEW_UI === 'true',
    enableCache: process.env.FEATURE_CACHE === 'true',
    enableMetrics: process.env.FEATURE_METRICS === 'true'
  },
  apiTimeout: parseInt(process.env.API_TIMEOUT || '5000'),
  logLevel: process.env.LOG_LEVEL || 'info',
  database: {
    host: process.env.DB_HOST || 'localhost',
    maxConnections: parseInt(process.env.DB_MAX_CONNECTIONS || '10')
  }
};

// Log configuration on startup
console.log('Application Configuration:', JSON.stringify(config, null, 2));

// Root endpoint - shows version info and config
app.get('/', (req, res) => {
  res.json({
    application: 'Blue-Green Demo',
    version: version,
    color: color,
    timestamp: new Date().toISOString(),
    hostname: require('os').hostname(),
    config: config
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

// Configuration endpoint - useful for debugging config issues
app.get('/config', (req, res) => {
  res.json({
    version: version,
    color: color,
    configuration: config
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
