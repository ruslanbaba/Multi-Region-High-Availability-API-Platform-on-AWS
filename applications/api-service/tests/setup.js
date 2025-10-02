// Global test setup
const { setupProcessHandlers } = require('../src/middleware/errorHandler');

// Setup global error handlers for tests
setupProcessHandlers();

// Mock console methods to reduce noise in tests
global.console = {
  ...console,
  log: jest.fn(),
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
};

// Global test timeout
jest.setTimeout(10000);

// Mock environment variables for tests
process.env.NODE_ENV = 'test';
process.env.LOG_LEVEL = 'error';
process.env.JWT_SECRET = 'test-jwt-secret-key';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-key';
process.env.API_KEY = 'test-api-key';
process.env.AWS_REGION = 'us-east-1';
process.env.DYNAMODB_USER_TABLE = 'test-users';

// Global mocks
jest.mock('../src/utils/logger', () => ({
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  fatal: jest.fn(),
}));

jest.mock('../src/utils/cache', () => ({
  get: jest.fn(),
  set: jest.fn(),
  del: jest.fn(),
  has: jest.fn(),
  keys: jest.fn(() => []),
  getStats: jest.fn(() => ({ keys: 0, hits: 0, misses: 0 })),
  flushAll: jest.fn(),
  close: jest.fn(),
  mget: jest.fn(),
  mset: jest.fn(),
  mdel: jest.fn(),
  getInfo: jest.fn(() => ({
    keys: 0,
    hits: 0,
    misses: 0,
    hitRate: 0,
    memory: process.memoryUsage(),
  })),
}));

jest.mock('../src/utils/metrics', () => ({
  recordRequestDuration: jest.fn(),
  recordError: jest.fn(),
  recordCacheHit: jest.fn(),
  recordCacheMiss: jest.fn(),
  getMetrics: jest.fn(() => ({})),
}));

// Global test utilities
global.testUtils = {
  createMockUser: (overrides = {}) => ({
    id: 'test-user-id',
    email: 'test@example.com',
    firstName: 'Test',
    lastName: 'User',
    roles: ['user'],
    isActive: true,
    emailVerified: true,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    ...overrides,
  }),

  createMockAdminUser: (overrides = {}) => ({
    id: 'admin-user-id',
    email: 'admin@example.com',
    firstName: 'Admin',
    lastName: 'User',
    roles: ['admin'],
    isActive: true,
    emailVerified: true,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    ...overrides,
  }),

  sleep: (ms) => new Promise(resolve => setTimeout(resolve, ms)),
};