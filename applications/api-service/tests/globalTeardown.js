// Global teardown for Jest tests
module.exports = async () => {
  console.log('Tearing down test environment...');

  // Clean up any global resources
  // Close any open connections, clear timers, etc.

  // Reset environment variables if needed
  delete process.env.TEST_ENV_SETUP;

  console.log('Test environment teardown complete');
};