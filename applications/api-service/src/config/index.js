require('dotenv').config();

const config = {
  // Server configuration
  port: process.env.PORT || 3000,
  environment: process.env.NODE_ENV || 'development',
  
  // AWS configuration
  aws: {
    region: process.env.AWS_REGION || 'us-east-1',
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },

  // Database configuration
  database: {
    tableName: process.env.DYNAMODB_TABLE_NAME || `${process.env.ENVIRONMENT || 'dev'}-api-platform-users`,
    region: process.env.AWS_REGION || 'us-east-1',
  },

  // Secrets Manager
  secrets: {
    secretName: process.env.SECRETS_MANAGER_SECRET_NAME || `${process.env.ENVIRONMENT || 'dev'}-api-platform-app-secrets`,
  },

  // CORS configuration
  cors: {
    allowedOrigins: process.env.CORS_ORIGINS ? process.env.CORS_ORIGINS.split(',') : ['http://localhost:3000'],
  },

  // Rate limiting
  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS, 10) || 900000, // 15 minutes
    max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS, 10) || 100, // 100 requests per windowMs
  },

  // JWT configuration
  jwt: {
    secret: process.env.JWT_SECRET || 'your-secret-key',
    expiresIn: process.env.JWT_EXPIRES_IN || '24h',
  },

  // Logging configuration
  logging: {
    level: process.env.LOG_LEVEL || 'info',
    pretty: process.env.NODE_ENV === 'development',
  },

  // Cache configuration
  cache: {
    ttl: parseInt(process.env.CACHE_TTL, 10) || 300, // 5 minutes
    checkPeriod: parseInt(process.env.CACHE_CHECK_PERIOD, 10) || 600, // 10 minutes
  },

  // Health check configuration
  healthCheck: {
    timeout: parseInt(process.env.HEALTH_CHECK_TIMEOUT, 10) || 5000, // 5 seconds
  },

  // Metrics configuration
  metrics: {
    enabled: process.env.METRICS_ENABLED !== 'false',
    namespace: process.env.METRICS_NAMESPACE || 'MultiRegionAPI',
  },

  // Application specific
  app: {
    name: 'Multi-Region API Platform',
    version: process.env.npm_package_version || '1.0.0',
  },
};

module.exports = config;