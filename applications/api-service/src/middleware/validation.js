const Joi = require('joi');
const { ValidationError } = require('./errorHandler');
const logger = require('../utils/logger');

/**
 * Generic validation middleware factory
 * @param {Object} schema - Joi validation schema
 * @param {string} property - Request property to validate (body, query, params)
 */
const validate = (schema, property = 'body') => {
  return (req, res, next) => {
    const { error, value } = schema.validate(req[property], {
      abortEarly: false, // Return all validation errors
      stripUnknown: true, // Remove unknown fields
      convert: true, // Convert strings to numbers, etc.
    });

    if (error) {
      const details = error.details.map(detail => ({
        field: detail.path.join('.'),
        message: detail.message,
        value: detail.context?.value,
      }));

      logger.warn({
        property,
        errors: details,
        originalData: req[property],
      }, 'Validation failed');

      throw new ValidationError('Validation failed', details);
    }

    // Replace request property with validated and sanitized value
    req[property] = value;
    next();
  };
};

/**
 * Common validation schemas
 */
const schemas = {
  // User schemas
  userRegistration: Joi.object({
    email: Joi.string()
      .email()
      .lowercase()
      .trim()
      .required()
      .messages({
        'string.email': 'Please provide a valid email address',
        'any.required': 'Email is required',
      }),
    password: Joi.string()
      .min(8)
      .max(128)
      .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/)
      .required()
      .messages({
        'string.min': 'Password must be at least 8 characters long',
        'string.max': 'Password must not exceed 128 characters',
        'string.pattern.base': 'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character',
        'any.required': 'Password is required',
      }),
    firstName: Joi.string()
      .min(1)
      .max(50)
      .trim()
      .required()
      .messages({
        'string.min': 'First name cannot be empty',
        'string.max': 'First name must not exceed 50 characters',
        'any.required': 'First name is required',
      }),
    lastName: Joi.string()
      .min(1)
      .max(50)
      .trim()
      .required()
      .messages({
        'string.min': 'Last name cannot be empty',
        'string.max': 'Last name must not exceed 50 characters',
        'any.required': 'Last name is required',
      }),
    phone: Joi.string()
      .pattern(/^\+?[\d\s\-\(\)]{10,}$/)
      .optional()
      .messages({
        'string.pattern.base': 'Please provide a valid phone number',
      }),
  }),

  userLogin: Joi.object({
    email: Joi.string()
      .email()
      .lowercase()
      .trim()
      .required()
      .messages({
        'string.email': 'Please provide a valid email address',
        'any.required': 'Email is required',
      }),
    password: Joi.string()
      .required()
      .messages({
        'any.required': 'Password is required',
      }),
  }),

  userUpdate: Joi.object({
    firstName: Joi.string()
      .min(1)
      .max(50)
      .trim()
      .optional(),
    lastName: Joi.string()
      .min(1)
      .max(50)
      .trim()
      .optional(),
    phone: Joi.string()
      .pattern(/^\+?[\d\s\-\(\)]{10,}$/)
      .optional()
      .allow(null, ''),
    bio: Joi.string()
      .max(500)
      .trim()
      .optional()
      .allow(null, ''),
  }).min(1), // At least one field must be provided

  passwordChange: Joi.object({
    currentPassword: Joi.string()
      .required()
      .messages({
        'any.required': 'Current password is required',
      }),
    newPassword: Joi.string()
      .min(8)
      .max(128)
      .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/)
      .required()
      .messages({
        'string.min': 'New password must be at least 8 characters long',
        'string.max': 'New password must not exceed 128 characters',
        'string.pattern.base': 'New password must contain at least one uppercase letter, one lowercase letter, one number, and one special character',
        'any.required': 'New password is required',
      }),
  }),

  // Parameter schemas
  mongoId: Joi.object({
    id: Joi.string()
      .pattern(/^[0-9a-fA-F]{24}$/)
      .required()
      .messages({
        'string.pattern.base': 'Invalid ID format',
        'any.required': 'ID is required',
      }),
  }),

  // Query schemas
  pagination: Joi.object({
    page: Joi.number()
      .integer()
      .min(1)
      .default(1)
      .messages({
        'number.base': 'Page must be a number',
        'number.integer': 'Page must be an integer',
        'number.min': 'Page must be at least 1',
      }),
    limit: Joi.number()
      .integer()
      .min(1)
      .max(100)
      .default(10)
      .messages({
        'number.base': 'Limit must be a number',
        'number.integer': 'Limit must be an integer',
        'number.min': 'Limit must be at least 1',
        'number.max': 'Limit must not exceed 100',
      }),
    sort: Joi.string()
      .valid('name', 'email', 'createdAt', 'updatedAt', '-name', '-email', '-createdAt', '-updatedAt')
      .default('createdAt')
      .messages({
        'any.only': 'Sort must be one of: name, email, createdAt, updatedAt (prefix with - for descending)',
      }),
    search: Joi.string()
      .min(1)
      .max(100)
      .trim()
      .optional()
      .messages({
        'string.min': 'Search term must be at least 1 character',
        'string.max': 'Search term must not exceed 100 characters',
      }),
  }),

  // Token schemas
  refreshToken: Joi.object({
    refreshToken: Joi.string()
      .required()
      .messages({
        'any.required': 'Refresh token is required',
      }),
  }),

  // Email verification
  emailVerification: Joi.object({
    token: Joi.string()
      .required()
      .messages({
        'any.required': 'Verification token is required',
      }),
  }),

  // Password reset
  passwordResetRequest: Joi.object({
    email: Joi.string()
      .email()
      .lowercase()
      .trim()
      .required()
      .messages({
        'string.email': 'Please provide a valid email address',
        'any.required': 'Email is required',
      }),
  }),

  passwordReset: Joi.object({
    token: Joi.string()
      .required()
      .messages({
        'any.required': 'Reset token is required',
      }),
    password: Joi.string()
      .min(8)
      .max(128)
      .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/)
      .required()
      .messages({
        'string.min': 'Password must be at least 8 characters long',
        'string.max': 'Password must not exceed 128 characters',
        'string.pattern.base': 'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character',
        'any.required': 'Password is required',
      }),
  }),
};

/**
 * Specific validation middleware functions
 */
const validateUserRegistration = validate(schemas.userRegistration, 'body');
const validateUserLogin = validate(schemas.userLogin, 'body');
const validateUserUpdate = validate(schemas.userUpdate, 'body');
const validatePasswordChange = validate(schemas.passwordChange, 'body');
const validateMongoId = validate(schemas.mongoId, 'params');
const validatePagination = validate(schemas.pagination, 'query');
const validateRefreshToken = validate(schemas.refreshToken, 'body');
const validateEmailVerification = validate(schemas.emailVerification, 'body');
const validatePasswordResetRequest = validate(schemas.passwordResetRequest, 'body');
const validatePasswordReset = validate(schemas.passwordReset, 'body');

/**
 * Custom validation functions
 */
const validateUnique = (field, model) => {
  return async (req, res, next) => {
    try {
      const value = req.body[field];
      if (!value) return next();

      // Skip validation if updating the same record with the same value
      if (req.params.id && req.user && req.user.id === req.params.id) {
        const existingUser = await model.findById(req.params.id);
        if (existingUser && existingUser[field] === value) {
          return next();
        }
      }

      const existing = await model.findOne({ [field]: value });
      if (existing) {
        throw new ValidationError(`${field} already exists`, [
          {
            field,
            message: `This ${field} is already taken`,
            value,
          }
        ]);
      }

      next();
    } catch (error) {
      next(error);
    }
  };
};

module.exports = {
  validate,
  schemas,
  // Specific validators
  validateUserRegistration,
  validateUserLogin,
  validateUserUpdate,
  validatePasswordChange,
  validateMongoId,
  validatePagination,
  validateRefreshToken,
  validateEmailVerification,
  validatePasswordResetRequest,
  validatePasswordReset,
  // Custom validators
  validateUnique,
};