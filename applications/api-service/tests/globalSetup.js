// Global setup for Jest tests
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

module.exports = async () => {
  console.log('Setting up test environment...');

  // Set test environment variables
  process.env.NODE_ENV = 'test';
  process.env.LOG_LEVEL = 'error';
  process.env.PORT = '0'; // Let the OS assign a port
  process.env.CACHE_TTL = '60';
  process.env.CACHE_CHECK_PERIOD = '60';

  // Mock AWS credentials for tests
  process.env.AWS_ACCESS_KEY_ID = 'test-access-key';
  process.env.AWS_SECRET_ACCESS_KEY = 'test-secret-key';
  process.env.AWS_REGION = 'us-east-1';

  // Mock database table names
  process.env.DYNAMODB_USER_TABLE = 'test-users-table';

  // Mock JWT secrets
  process.env.JWT_SECRET = 'test-jwt-secret-that-is-long-enough-for-security';
  process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-that-is-long-enough-for-security';
  process.env.JWT_EXPIRES_IN = '15m';
  process.env.JWT_REFRESH_EXPIRES_IN = '7d';

  // Mock API keys
  process.env.API_KEY = 'test-api-key-for-service-authentication';

  // Mock service configuration
  process.env.SERVICE_NAME = 'test-api-service';
  process.env.SERVICE_VERSION = '1.0.0';

  // Mock external service URLs
  process.env.HEALTH_CHECK_TIMEOUT = '5000';
  process.env.REQUEST_TIMEOUT = '30000';

  console.log('Test environment setup complete');
};