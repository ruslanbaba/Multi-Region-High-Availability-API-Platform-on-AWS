const bcrypt = require('bcrypt');
const BaseDatabase = require('./base');
const config = require('../config');
const logger = require('../utils/logger');
const { ConflictError, NotFoundError } = require('../middleware/errorHandler');

/**
 * User Database Class
 * Handles all user-related database operations
 */
class UserDatabase extends BaseDatabase {
  constructor() {
    super(config.dynamodb.userTable);
    this.emailIndex = 'email-index';
  }

  /**
   * Create a new user with hashed password
   */
  async createUser(userData) {
    try {
      // Check if email already exists
      const existingUser = await this.findByEmail(userData.email);
      if (existingUser) {
        throw new ConflictError('User with this email already exists');
      }

      // Hash password
      const saltRounds = 12;
      const hashedPassword = await bcrypt.hash(userData.password, saltRounds);

      // Prepare user data
      const user = {
        id: this.generateId(),
        email: userData.email.toLowerCase().trim(),
        password: hashedPassword,
        firstName: userData.firstName.trim(),
        lastName: userData.lastName.trim(),
        phone: userData.phone || null,
        bio: userData.bio || null,
        roles: userData.roles || ['user'],
        isActive: true,
        emailVerified: false,
        lastLoginAt: null,
        loginAttempts: 0,
        lockedUntil: null,
        profilePicture: null,
        preferences: {
          theme: 'light',
          notifications: {
            email: true,
            push: false,
          },
        },
        metadata: {
          registrationIp: userData.ip || null,
          registrationUserAgent: userData.userAgent || null,
        },
      };

      const createdUser = await this.create(user);
      
      // Remove password from response
      const { password, ...userWithoutPassword } = createdUser;
      
      logger.info({ 
        userId: createdUser.id, 
        email: createdUser.email 
      }, 'User created successfully');
      
      return userWithoutPassword;
    } catch (error) {
      if (error instanceof ConflictError) {
        throw error;
      }
      
      logger.error({ 
        error: error.message, 
        email: userData.email 
      }, 'Failed to create user');
      throw new Error('Failed to create user');
    }
  }

  /**
   * Find user by email
   */
  async findByEmail(email, includePassword = false) {
    try {
      const params = {
        indexName: this.emailIndex,
        expressionAttributeNames: {
          '#email': 'email',
        },
        expressionAttributeValues: {
          ':email': email.toLowerCase().trim(),
        },
      };

      const result = await this.query('#email = :email', params);
      
      if (result.items.length === 0) {
        return null;
      }

      const user = result.items[0];
      
      if (!includePassword) {
        const { password, ...userWithoutPassword } = user;
        return userWithoutPassword;
      }
      
      return user;
    } catch (error) {
      logger.error({ 
        error: error.message, 
        email 
      }, 'Failed to find user by email');
      throw error;
    }
  }

  /**
   * Authenticate user with email and password
   */
  async authenticateUser(email, password) {
    try {
      const user = await this.findByEmail(email, true);
      
      if (!user) {
        throw new NotFoundError('Invalid email or password');
      }

      // Check if account is locked
      if (user.lockedUntil && new Date() < new Date(user.lockedUntil)) {
        const lockTimeRemaining = Math.ceil((new Date(user.lockedUntil) - new Date()) / 60000);
        throw new Error(`Account is locked. Try again in ${lockTimeRemaining} minutes.`);
      }

      // Check if account is active
      if (!user.isActive) {
        throw new Error('Account is deactivated. Please contact support.');
      }

      // Verify password
      const isValidPassword = await bcrypt.compare(password, user.password);
      
      if (!isValidPassword) {
        // Increment login attempts
        await this.incrementLoginAttempts(user.id);
        throw new NotFoundError('Invalid email or password');
      }

      // Reset login attempts and update last login
      await this.updateById(user.id, {
        lastLoginAt: new Date().toISOString(),
        loginAttempts: 0,
        lockedUntil: null,
      });

      // Remove password from response
      const { password: _, ...userWithoutPassword } = user;
      
      logger.info({ 
        userId: user.id, 
        email: user.email 
      }, 'User authenticated successfully');
      
      return userWithoutPassword;
    } catch (error) {
      if (error instanceof NotFoundError || error.message.includes('locked') || error.message.includes('deactivated')) {
        throw error;
      }
      
      logger.error({ 
        error: error.message, 
        email 
      }, 'Failed to authenticate user');
      throw new Error('Authentication failed');
    }
  }

  /**
   * Update user password
   */
  async updatePassword(userId, currentPassword, newPassword) {
    try {
      const user = await this.findById(userId);
      if (!user) {
        throw new NotFoundError('User not found');
      }

      // Get user with password for verification
      const userWithPassword = await this.findByEmail(user.email, true);
      
      // Verify current password
      const isValidPassword = await bcrypt.compare(currentPassword, userWithPassword.password);
      if (!isValidPassword) {
        throw new Error('Current password is incorrect');
      }

      // Hash new password
      const saltRounds = 12;
      const hashedPassword = await bcrypt.hash(newPassword, saltRounds);

      // Update password
      await this.updateById(userId, {
        password: hashedPassword,
      });

      logger.info({ userId }, 'User password updated successfully');
      
      return { message: 'Password updated successfully' };
    } catch (error) {
      if (error instanceof NotFoundError || error.message.includes('incorrect')) {
        throw error;
      }
      
      logger.error({ 
        error: error.message, 
        userId 
      }, 'Failed to update user password');
      throw new Error('Failed to update password');
    }
  }

  /**
   * Get user profile (without sensitive data)
   */
  async getUserProfile(userId) {
    try {
      const user = await this.findById(userId);
      if (!user) {
        throw new NotFoundError('User not found');
      }

      // Remove sensitive fields
      const {
        password,
        loginAttempts,
        lockedUntil,
        metadata,
        ...profile
      } = user;

      return profile;
    } catch (error) {
      if (error instanceof NotFoundError) {
        throw error;
      }
      
      logger.error({ 
        error: error.message, 
        userId 
      }, 'Failed to get user profile');
      throw error;
    }
  }

  /**
   * Update user profile
   */
  async updateUserProfile(userId, updates) {
    try {
      const user = await this.findById(userId);
      if (!user) {
        throw new NotFoundError('User not found');
      }

      // Only allow certain fields to be updated
      const allowedUpdates = {
        firstName: updates.firstName,
        lastName: updates.lastName,
        phone: updates.phone,
        bio: updates.bio,
        profilePicture: updates.profilePicture,
        preferences: updates.preferences,
      };

      // Remove undefined values
      const cleanUpdates = this.cleanUpdates(allowedUpdates);

      if (Object.keys(cleanUpdates).length === 0) {
        return user;
      }

      const updatedUser = await this.updateById(userId, cleanUpdates);
      
      // Remove sensitive fields
      const {
        password,
        loginAttempts,
        lockedUntil,
        metadata,
        ...profile
      } = updatedUser;

      logger.info({ 
        userId, 
        updatedFields: Object.keys(cleanUpdates) 
      }, 'User profile updated successfully');

      return profile;
    } catch (error) {
      if (error instanceof NotFoundError) {
        throw error;
      }
      
      logger.error({ 
        error: error.message, 
        userId, 
        updates 
      }, 'Failed to update user profile');
      throw error;
    }
  }

  /**
   * Get users with pagination and filtering
   */
  async getUsers(options = {}) {
    try {
      const {
        limit = 10,
        lastEvaluatedKey = null,
        search = null,
        role = null,
        isActive = null,
      } = options;

      let filterExpression = null;
      const expressionAttributeNames = {};
      const expressionAttributeValues = {};

      // Build filter expression
      const filters = [];

      if (search) {
        filters.push('(contains(firstName, :search) OR contains(lastName, :search) OR contains(email, :search))');
        expressionAttributeValues[':search'] = search;
      }

      if (role) {
        filters.push('contains(#roles, :role)');
        expressionAttributeNames['#roles'] = 'roles';
        expressionAttributeValues[':role'] = role;
      }

      if (isActive !== null) {
        filters.push('#isActive = :isActive');
        expressionAttributeNames['#isActive'] = 'isActive';
        expressionAttributeValues[':isActive'] = isActive;
      }

      if (filters.length > 0) {
        filterExpression = filters.join(' AND ');
      }

      const result = await this.find({
        limit,
        lastEvaluatedKey,
        filterExpression,
        expressionAttributeNames,
        expressionAttributeValues,
      });

      // Remove sensitive data from all users
      const users = result.items.map(user => {
        const {
          password,
          loginAttempts,
          lockedUntil,
          metadata,
          ...safeUser
        } = user;
        return safeUser;
      });

      return {
        ...result,
        items: users,
      };
    } catch (error) {
      logger.error({ 
        error: error.message, 
        options 
      }, 'Failed to get users');
      throw error;
    }
  }

  /**
   * Deactivate user account
   */
  async deactivateUser(userId) {
    try {
      const updatedUser = await this.updateById(userId, {
        isActive: false,
      });

      logger.info({ userId }, 'User account deactivated');
      
      return { message: 'User account deactivated successfully' };
    } catch (error) {
      if (error.message.includes('not found')) {
        throw new NotFoundError('User not found');
      }
      
      logger.error({ 
        error: error.message, 
        userId 
      }, 'Failed to deactivate user');
      throw error;
    }
  }

  /**
   * Activate user account
   */
  async activateUser(userId) {
    try {
      const updatedUser = await this.updateById(userId, {
        isActive: true,
        loginAttempts: 0,
        lockedUntil: null,
      });

      logger.info({ userId }, 'User account activated');
      
      return { message: 'User account activated successfully' };
    } catch (error) {
      if (error.message.includes('not found')) {
        throw new NotFoundError('User not found');
      }
      
      logger.error({ 
        error: error.message, 
        userId 
      }, 'Failed to activate user');
      throw error;
    }
  }

  /**
   * Increment login attempts and lock account if necessary
   */
  async incrementLoginAttempts(userId) {
    try {
      const user = await this.findById(userId);
      if (!user) return;

      const newAttempts = (user.loginAttempts || 0) + 1;
      const maxAttempts = 5;
      const lockDuration = 30 * 60 * 1000; // 30 minutes

      const updates = {
        loginAttempts: newAttempts,
      };

      // Lock account if max attempts reached
      if (newAttempts >= maxAttempts) {
        updates.lockedUntil = new Date(Date.now() + lockDuration).toISOString();
        logger.warn({ 
          userId, 
          attempts: newAttempts 
        }, 'User account locked due to too many failed login attempts');
      }

      await this.updateById(userId, updates);
    } catch (error) {
      logger.error({ 
        error: error.message, 
        userId 
      }, 'Failed to increment login attempts');
    }
  }

  /**
   * Verify user email
   */
  async verifyEmail(userId) {
    try {
      const updatedUser = await this.updateById(userId, {
        emailVerified: true,
      });

      logger.info({ userId }, 'User email verified');
      
      return { message: 'Email verified successfully' };
    } catch (error) {
      if (error.message.includes('not found')) {
        throw new NotFoundError('User not found');
      }
      
      logger.error({ 
        error: error.message, 
        userId 
      }, 'Failed to verify email');
      throw error;
    }
  }

  /**
   * Database health check specific to users table
   */
  async healthCheck() {
    try {
      const baseHealth = await super.healthCheck();
      
      // Additional checks for users table
      const userCount = await this.getUserCount();
      
      return {
        ...baseHealth,
        userCount,
        indexes: [this.emailIndex],
      };
    } catch (error) {
      return {
        status: 'unhealthy',
        table: this.tableName,
        error: error.message,
      };
    }
  }

  /**
   * Get total user count (for health checks and admin dashboard)
   */
  async getUserCount() {
    try {
      const result = await this.find({ limit: 1 });
      return result.scannedCount || 0;
    } catch (error) {
      logger.error({ error: error.message }, 'Failed to get user count');
      return 0;
    }
  }
}

module.exports = UserDatabase;