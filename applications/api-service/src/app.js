const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const promClient = require('prom-client');
const promApiMetrics = require('prometheus-api-metrics');
const AWSXRay = require('aws-xray-sdk-express');
const pinoLogger = require('express-pino-logger');
const config = require('./config');
const logger = require('./utils/logger');
const healthCheck = require('./routes/health');
const apiRoutes = require('./routes/api');
const userRoutes = require('./routes/users');
const errorHandler = require('./middleware/errorHandler');
const requestId = require('./middleware/requestId');
const validateRequest = require('./middleware/validation');

// Create Express app
const app = express();

// X-Ray tracing (only in AWS environment)
if (process.env.AWS_XRAY_TRACING_NAME) {
  app.use(AWSXRay.express.openSegment('MultiRegionAPI'));
}

// Trust proxy for load balancer
app.set('trust proxy', 1);

// Security middleware
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:"],
    },
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true,
  },
}));

// CORS configuration
app.use(cors({
  origin: config.cors.allowedOrigins,
  credentials: true,
  optionsSuccessStatus: 200,
}));

// Compression
app.use(compression());

// Rate limiting
const limiter = rateLimit({
  windowMs: config.rateLimit.windowMs,
  max: config.rateLimit.max,
  message: {
    error: 'Too many requests from this IP, please try again later.',
  },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api/', limiter);

// Prometheus metrics
app.use(promApiMetrics({
  metricsPath: '/metrics',
  defaultMetrics: true,
  requestDurationBuckets: [0.1, 0.5, 1, 1.5, 2, 3, 5, 10],
  requestLengthBuckets: [512, 1024, 5120, 10240, 51200, 102400],
  responseLengthBuckets: [512, 1024, 5120, 10240, 51200, 102400],
}));

// Request ID middleware
app.use(requestId);

// Logging middleware
app.use(pinoLogger({ logger }));

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Routes
app.use('/health', healthCheck);
app.use('/api/v1', apiRoutes);
app.use('/api/v1/users', userRoutes);

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'Multi-Region API Platform',
    version: process.env.npm_package_version || '1.0.0',
    environment: config.environment,
    region: config.aws.region,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Not Found',
    message: 'The requested resource was not found',
    path: req.originalUrl,
    timestamp: new Date().toISOString(),
  });
});

// Error handling middleware
app.use(errorHandler);

// X-Ray tracing close segment
if (process.env.AWS_XRAY_TRACING_NAME) {
  app.use(AWSXRay.express.closeSegment());
}

module.exports = app;