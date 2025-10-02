const app = require('./app');
const config = require('./config');
const logger = require('./utils/logger');
const db = require('./db');
const { initializeMetrics } = require('./utils/metrics');

// Initialize metrics
initializeMetrics();

// Graceful shutdown
const gracefulShutdown = (signal) => {
  logger.info(`Received ${signal}. Starting graceful shutdown...`);
  
  server.close(() => {
    logger.info('HTTP server closed');
    
    // Close database connections
    db.close()
      .then(() => {
        logger.info('Database connections closed');
        process.exit(0);
      })
      .catch((error) => {
        logger.error('Error closing database connections:', error);
        process.exit(1);
      });
  });

  // Force close after 30 seconds
  setTimeout(() => {
    logger.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 30000);
};

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  logger.error('Uncaught exception:', error);
  process.exit(1);
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

// Handle termination signals
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Start server
const server = app.listen(config.port, () => {
  logger.info({
    message: 'Server started successfully',
    port: config.port,
    environment: config.environment,
    region: config.aws.region,
    pid: process.pid,
    nodeVersion: process.version,
  });
});

// Set server timeout
server.timeout = 120000; // 2 minutes

module.exports = server;