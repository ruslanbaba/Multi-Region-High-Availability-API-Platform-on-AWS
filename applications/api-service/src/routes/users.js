const express = require('express');
const { body, validationResult } = require('express-validator');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const config = require('../config');
const db = require('../db');
const logger = require('../utils/logger');
const { recordMetric } = require('../utils/metrics');
const authMiddleware = require('../middleware/auth');
const cache = require('../utils/cache');

const router = express.Router();

// Validation schemas
const createUserValidation = [
  body('email').isEmail().normalizeEmail(),
  body('password').isLength({ min: 8 }).matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/),
  body('name').isLength({ min: 2, max: 50 }).trim(),
];

const loginValidation = [
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
];

const updateUserValidation = [
  body('name').optional().isLength({ min: 2, max: 50 }).trim(),
  body('email').optional().isEmail().normalizeEmail(),
];

// Create user
router.post('/', createUserValidation, async (req, res) => {
  try {
    // Check validation errors
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      recordMetric('user_creation_validation_error', 1);
      return res.status(400).json({
        error: 'Validation failed',
        details: errors.array(),
      });
    }

    const { email, password, name } = req.body;
    const userId = uuidv4();

    // Check if user already exists
    const existingUser = await db.getUserByEmail(email);
    if (existingUser) {
      recordMetric('user_creation_duplicate_email', 1);
      return res.status(409).json({
        error: 'User already exists',
        message: 'A user with this email already exists',
      });
    }

    // Hash password
    const saltRounds = 12;
    const hashedPassword = await bcrypt.hash(password, saltRounds);

    // Create user
    const userData = {
      id: userId,
      email,
      name,
      password: hashedPassword,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      isActive: true,
    };

    await db.createUser(userData);

    // Remove password from response
    const { password: _, ...userResponse } = userData;

    recordMetric('user_created', 1);
    logger.info({ userId, email }, 'User created successfully');

    res.status(201).json({
      message: 'User created successfully',
      user: userResponse,
    });

  } catch (error) {
    recordMetric('user_creation_error', 1);
    logger.error({ error: error.message, stack: error.stack }, 'Error creating user');
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to create user',
    });
  }
});

// Login user
router.post('/login', loginValidation, async (req, res) => {
  try {
    // Check validation errors
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      recordMetric('user_login_validation_error', 1);
      return res.status(400).json({
        error: 'Validation failed',
        details: errors.array(),
      });
    }

    const { email, password } = req.body;

    // Get user by email
    const user = await db.getUserByEmail(email);
    if (!user) {
      recordMetric('user_login_invalid_credentials', 1);
      return res.status(401).json({
        error: 'Invalid credentials',
        message: 'Email or password is incorrect',
      });
    }

    // Check if user is active
    if (!user.isActive) {
      recordMetric('user_login_inactive_account', 1);
      return res.status(401).json({
        error: 'Account inactive',
        message: 'Your account has been deactivated',
      });
    }

    // Verify password
    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      recordMetric('user_login_invalid_credentials', 1);
      return res.status(401).json({
        error: 'Invalid credentials',
        message: 'Email or password is incorrect',
      });
    }

    // Generate JWT token
    const token = jwt.sign(
      { 
        userId: user.id, 
        email: user.email,
        name: user.name,
      },
      config.jwt.secret,
      { expiresIn: config.jwt.expiresIn }
    );

    // Update last login
    await db.updateUserLastLogin(user.id);

    // Remove password from response
    const { password: _, ...userResponse } = user;

    recordMetric('user_login_success', 1);
    logger.info({ userId: user.id, email }, 'User logged in successfully');

    res.json({
      message: 'Login successful',
      token,
      user: userResponse,
    });

  } catch (error) {
    recordMetric('user_login_error', 1);
    logger.error({ error: error.message, stack: error.stack }, 'Error during login');
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to process login',
    });
  }
});

// Get current user
router.get('/me', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;

    // Try to get from cache first
    const cacheKey = `user:${userId}`;
    let user = cache.get(cacheKey);

    if (!user) {
      user = await db.getUserById(userId);
      if (!user) {
        return res.status(404).json({
          error: 'User not found',
          message: 'User does not exist',
        });
      }

      // Cache user data for 5 minutes
      cache.set(cacheKey, user, 300);
    }

    // Remove password from response
    const { password: _, ...userResponse } = user;

    recordMetric('user_profile_accessed', 1);

    res.json({
      user: userResponse,
    });

  } catch (error) {
    recordMetric('user_profile_error', 1);
    logger.error({ error: error.message, stack: error.stack }, 'Error getting user profile');
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to get user profile',
    });
  }
});

// Update user
router.put('/me', authMiddleware, updateUserValidation, async (req, res) => {
  try {
    // Check validation errors
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      recordMetric('user_update_validation_error', 1);
      return res.status(400).json({
        error: 'Validation failed',
        details: errors.array(),
      });
    }

    const userId = req.user.userId;
    const { name, email } = req.body;

    // Get current user
    const currentUser = await db.getUserById(userId);
    if (!currentUser) {
      return res.status(404).json({
        error: 'User not found',
        message: 'User does not exist',
      });
    }

    // Check if email is being changed and if it's already taken
    if (email && email !== currentUser.email) {
      const existingUser = await db.getUserByEmail(email);
      if (existingUser) {
        recordMetric('user_update_duplicate_email', 1);
        return res.status(409).json({
          error: 'Email already exists',
          message: 'A user with this email already exists',
        });
      }
    }

    // Update user data
    const updateData = {
      ...(name && { name }),
      ...(email && { email }),
      updatedAt: new Date().toISOString(),
    };

    const updatedUser = await db.updateUser(userId, updateData);

    // Clear cache
    cache.del(`user:${userId}`);

    // Remove password from response
    const { password: _, ...userResponse } = updatedUser;

    recordMetric('user_updated', 1);
    logger.info({ userId, updateData }, 'User updated successfully');

    res.json({
      message: 'User updated successfully',
      user: userResponse,
    });

  } catch (error) {
    recordMetric('user_update_error', 1);
    logger.error({ error: error.message, stack: error.stack }, 'Error updating user');
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to update user',
    });
  }
});

// Delete user
router.delete('/me', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.userId;

    // Soft delete by deactivating account
    await db.updateUser(userId, {
      isActive: false,
      deactivatedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

    // Clear cache
    cache.del(`user:${userId}`);

    recordMetric('user_deleted', 1);
    logger.info({ userId }, 'User account deactivated');

    res.json({
      message: 'Account deactivated successfully',
    });

  } catch (error) {
    recordMetric('user_delete_error', 1);
    logger.error({ error: error.message, stack: error.stack }, 'Error deleting user');
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to delete user',
    });
  }
});

// List users (admin endpoint)
router.get('/', authMiddleware, async (req, res) => {
  try {
    const { page = 1, limit = 10, search = '' } = req.query;
    const offset = (page - 1) * limit;

    const { users, total } = await db.getUsersList({
      limit: parseInt(limit, 10),
      offset: parseInt(offset, 10),
      search,
    });

    // Remove passwords from response
    const usersResponse = users.map(user => {
      const { password: _, ...userWithoutPassword } = user;
      return userWithoutPassword;
    });

    recordMetric('users_list_accessed', 1);

    res.json({
      users: usersResponse,
      pagination: {
        page: parseInt(page, 10),
        limit: parseInt(limit, 10),
        total,
        pages: Math.ceil(total / limit),
      },
    });

  } catch (error) {
    recordMetric('users_list_error', 1);
    logger.error({ error: error.message, stack: error.stack }, 'Error getting users list');
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to get users list',
    });
  }
});

module.exports = router;