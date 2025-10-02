const jwt = require('jsonwebtoken');
const { promisify } = require('util');
const config = require('../config');
const logger = require('../utils/logger');
const { recordRequestDuration } = require('../utils/metrics');

/**
 * JWT Authentication Middleware
 * Validates JWT tokens and sets user context
 */
const authenticate = async (req, res, next) => {
  const start = Date.now();
  
  try {
    // Get token from Authorization header
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        error: 'Authentication required',
        message: 'Missing or invalid Authorization header',
      });
    }

    const token = authHeader.substring(7); // Remove 'Bearer ' prefix

    // Verify JWT token
    const verifyAsync = promisify(jwt.verify);
    const decoded = await verifyAsync(token, config.jwt.secret);

    // Add user to request context
    req.user = decoded;
    
    logger.debug({ userId: decoded.id, tokenExp: decoded.exp }, 'User authenticated successfully');
    
    next();
  } catch (error) {
    logger.warn({ error: error.message, ip: req.ip }, 'Authentication failed');
    
    let message = 'Invalid token';
    if (error.name === 'TokenExpiredError') {
      message = 'Token has expired';
    } else if (error.name === 'JsonWebTokenError') {
      message = 'Invalid token format';
    }

    return res.status(401).json({
      error: 'Authentication failed',
      message,
    });
  } finally {
    recordRequestDuration('auth_middleware', Date.now() - start);
  }
};

/**
 * Optional Authentication Middleware
 * Validates JWT tokens if present but doesn't require them
 */
const optionalAuth = async (req, res, next) => {
  const authHeader = req.headers.authorization;
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return next(); // Continue without authentication
  }

  try {
    const token = authHeader.substring(7);
    const verifyAsync = promisify(jwt.verify);
    const decoded = await verifyAsync(token, config.jwt.secret);
    req.user = decoded;
    
    logger.debug({ userId: decoded.id }, 'Optional authentication successful');
  } catch (error) {
    // Log but don't fail the request
    logger.debug({ error: error.message }, 'Optional authentication failed');
  }

  next();
};

/**
 * Role-based Authorization Middleware
 * Requires specific roles for access
 */
const authorize = (requiredRoles = []) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        error: 'Authentication required',
        message: 'User not authenticated',
      });
    }

    const userRoles = req.user.roles || [];
    const hasRequiredRole = requiredRoles.some(role => userRoles.includes(role));

    if (requiredRoles.length > 0 && !hasRequiredRole) {
      logger.warn({
        userId: req.user.id,
        userRoles,
        requiredRoles,
      }, 'Authorization failed - insufficient permissions');

      return res.status(403).json({
        error: 'Insufficient permissions',
        message: `Required roles: ${requiredRoles.join(', ')}`,
      });
    }

    logger.debug({
      userId: req.user.id,
      userRoles,
      requiredRoles,
    }, 'Authorization successful');

    next();
  };
};

/**
 * Admin Only Middleware
 * Shorthand for admin role requirement
 */
const adminOnly = authorize(['admin']);

/**
 * User Self or Admin Middleware
 * Allows users to access their own resources or admins to access any
 */
const selfOrAdmin = (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({
      error: 'Authentication required',
      message: 'User not authenticated',
    });
  }

  const userId = req.params.id || req.params.userId;
  const isOwner = req.user.id === userId;
  const isAdmin = req.user.roles && req.user.roles.includes('admin');

  if (!isOwner && !isAdmin) {
    logger.warn({
      userId: req.user.id,
      requestedUserId: userId,
      userRoles: req.user.roles,
    }, 'Authorization failed - not owner or admin');

    return res.status(403).json({
      error: 'Insufficient permissions',
      message: 'You can only access your own resources',
    });
  }

  next();
};

/**
 * API Key Authentication Middleware
 * For service-to-service communication
 */
const apiKeyAuth = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  
  if (!apiKey) {
    return res.status(401).json({
      error: 'API key required',
      message: 'Missing X-API-Key header',
    });
  }

  if (apiKey !== config.auth.apiKey) {
    logger.warn({ ip: req.ip }, 'Invalid API key attempt');
    return res.status(401).json({
      error: 'Invalid API key',
      message: 'The provided API key is not valid',
    });
  }

  // Set service context
  req.service = { name: 'api-client', type: 'service' };
  
  next();
};

/**
 * Generate JWT Token
 */
const generateToken = (user) => {
  const payload = {
    id: user.id,
    email: user.email,
    roles: user.roles || ['user'],
    iat: Math.floor(Date.now() / 1000),
  };

  return jwt.sign(payload, config.jwt.secret, {
    expiresIn: config.jwt.expiresIn,
    issuer: config.auth.issuer,
    audience: config.auth.audience,
  });
};

/**
 * Generate Refresh Token
 */
const generateRefreshToken = (user) => {
  const payload = {
    id: user.id,
    type: 'refresh',
    iat: Math.floor(Date.now() / 1000),
  };

  return jwt.sign(payload, config.jwt.refreshSecret, {
    expiresIn: config.jwt.refreshExpiresIn,
    issuer: config.auth.issuer,
    audience: config.auth.audience,
  });
};

module.exports = {
  authenticate,
  optionalAuth,
  authorize,
  adminOnly,
  selfOrAdmin,
  apiKeyAuth,
  generateToken,
  generateRefreshToken,
};