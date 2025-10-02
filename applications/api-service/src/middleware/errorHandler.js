const logger = require('../utils/logger');
const { recordError } = require('../utils/metrics');
const config = require('../config');

/**
 * Global Error Handler Middleware
 * Handles all errors and sends appropriate responses
 */
const errorHandler = (err, req, res, next) => {
  // Record error metrics
  recordError(err.name || 'UnknownError');
  
  // Log error with context
  const errorContext = {
    error: {
      name: err.name,
      message: err.message,
      stack: err.stack,
    },
    request: {
      method: req.method,
      url: req.originalUrl,
      ip: req.ip,
      userAgent: req.get('User-Agent'),
      userId: req.user?.id,
    },
  };

  // Log based on error severity
  if (err.statusCode >= 500 || !err.statusCode) {
    logger.error(errorContext, 'Internal server error');
  } else {
    logger.warn(errorContext, 'Client error');
  }

  // Default error response
  let statusCode = err.statusCode || 500;
  let message = 'Internal server error';
  let details = null;

  // Handle specific error types
  switch (err.name) {
    case 'ValidationError':
      statusCode = 400;
      message = 'Validation failed';
      details = err.details || err.message;
      break;

    case 'UnauthorizedError':
    case 'JsonWebTokenError':
    case 'TokenExpiredError':
      statusCode = 401;
      message = 'Authentication failed';
      details = err.message;
      break;

    case 'ForbiddenError':
      statusCode = 403;
      message = 'Access forbidden';
      details = err.message;
      break;

    case 'NotFoundError':
      statusCode = 404;
      message = 'Resource not found';
      details = err.message;
      break;

    case 'ConflictError':
      statusCode = 409;
      message = 'Resource conflict';
      details = err.message;
      break;

    case 'TooManyRequestsError':
      statusCode = 429;
      message = 'Too many requests';
      details = err.message;
      break;

    case 'ServiceUnavailableError':
      statusCode = 503;
      message = 'Service temporarily unavailable';
      details = err.message;
      break;

    default:
      if (err.statusCode) {
        statusCode = err.statusCode;
        message = err.message || message;
      }
  }

  // Prepare error response
  const errorResponse = {
    error: message,
    ...(details && { details }),
    timestamp: new Date().toISOString(),
    path: req.originalUrl,
    method: req.method,
  };

  // Add request ID if available
  if (req.id) {
    errorResponse.requestId = req.id;
  }

  // Include stack trace in development
  if (config.nodeEnv === 'development' && err.stack) {
    errorResponse.stack = err.stack;
  }

  // Send error response
  res.status(statusCode).json(errorResponse);
};

/**
 * Not Found Handler
 * Handles 404 errors for undefined routes
 */
const notFoundHandler = (req, res, next) => {
  const error = new Error(`Route ${req.method} ${req.originalUrl} not found`);
  error.statusCode = 404;
  error.name = 'NotFoundError';
  next(error);
};

/**
 * Async Error Wrapper
 * Wraps async route handlers to catch errors
 */
const asyncHandler = (fn) => {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
};

/**
 * Custom Error Classes
 */
class AppError extends Error {
  constructor(message, statusCode = 500, name = 'AppError') {
    super(message);
    this.statusCode = statusCode;
    this.name = name;
    this.isOperational = true;
    Error.captureStackTrace(this, this.constructor);
  }
}

class ValidationError extends AppError {
  constructor(message, details = null) {
    super(message, 400, 'ValidationError');
    this.details = details;
  }
}

class UnauthorizedError extends AppError {
  constructor(message = 'Authentication required') {
    super(message, 401, 'UnauthorizedError');
  }
}

class ForbiddenError extends AppError {
  constructor(message = 'Access forbidden') {
    super(message, 403, 'ForbiddenError');
  }
}

class NotFoundError extends AppError {
  constructor(message = 'Resource not found') {
    super(message, 404, 'NotFoundError');
  }
}

class ConflictError extends AppError {
  constructor(message = 'Resource conflict') {
    super(message, 409, 'ConflictError');
  }
}

class TooManyRequestsError extends AppError {
  constructor(message = 'Too many requests') {
    super(message, 429, 'TooManyRequestsError');
  }
}

class ServiceUnavailableError extends AppError {
  constructor(message = 'Service temporarily unavailable') {
    super(message, 503, 'ServiceUnavailableError');
  }
}

/**
 * Process Exit Handler
 * Handles uncaught exceptions and unhandled rejections
 */
const setupProcessHandlers = () => {
  process.on('uncaughtException', (err) => {
    logger.fatal({ err }, 'Uncaught exception - shutting down');
    recordError('UncaughtException');
    process.exit(1);
  });

  process.on('unhandledRejection', (reason, promise) => {
    logger.fatal({ reason, promise }, 'Unhandled rejection - shutting down');
    recordError('UnhandledRejection');
    process.exit(1);
  });

  process.on('SIGTERM', () => {
    logger.info('SIGTERM received - starting graceful shutdown');
    process.exit(0);
  });

  process.on('SIGINT', () => {
    logger.info('SIGINT received - starting graceful shutdown');
    process.exit(0);
  });
};

module.exports = {
  errorHandler,
  notFoundHandler,
  asyncHandler,
  setupProcessHandlers,
  // Error classes
  AppError,
  ValidationError,
  UnauthorizedError,
  ForbiddenError,
  NotFoundError,
  ConflictError,
  TooManyRequestsError,
  ServiceUnavailableError,
};