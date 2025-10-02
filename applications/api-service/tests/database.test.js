const UserDatabase = require('../src/db/users');
const BaseDatabase = require('../src/db/base');
const bcrypt = require('bcrypt');
const { ConflictError, NotFoundError } = require('../src/middleware/errorHandler');

// Mock AWS SDK
jest.mock('aws-sdk', () => ({
  config: {
    update: jest.fn(),
  },
  DynamoDB: {
    DocumentClient: jest.fn(() => ({
      put: jest.fn(() => ({ promise: jest.fn() })),
      get: jest.fn(() => ({ promise: jest.fn() })),
      update: jest.fn(() => ({ promise: jest.fn() })),
      delete: jest.fn(() => ({ promise: jest.fn() })),
      scan: jest.fn(() => ({ promise: jest.fn() })),
      query: jest.fn(() => ({ promise: jest.fn() })),
      batchWrite: jest.fn(() => ({ promise: jest.fn() })),
    })),
  },
}));

// Mock bcrypt
jest.mock('bcrypt');

// Mock logger
jest.mock('../src/utils/logger', () => ({
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

// Mock cache
jest.mock('../src/utils/cache', () => ({
  get: jest.fn(),
  set: jest.fn(),
  del: jest.fn(),
  getInfo: jest.fn(() => ({ keys: 0, hits: 0, misses: 0 })),
}));

describe('UserDatabase', () => {
  let userDb;
  let mockClient;

  beforeEach(() => {
    userDb = new UserDatabase();
    mockClient = userDb.client;
    jest.clearAllMocks();
  });

  describe('createUser', () => {
    const userData = {
      email: 'test@example.com',
      password: 'password123',
      firstName: 'John',
      lastName: 'Doe',
    };

    it('should create a user successfully', async () => {
      // Mock query to return no existing user
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Items: [] }),
      });

      // Mock bcrypt hash
      bcrypt.hash.mockResolvedValue('hashedpassword');

      // Mock put operation
      mockClient.put.mockReturnValue({
        promise: jest.fn().mockResolvedValue({}),
      });

      const result = await userDb.createUser(userData);

      expect(result).toMatchObject({
        email: userData.email.toLowerCase(),
        firstName: userData.firstName,
        lastName: userData.lastName,
        roles: ['user'],
        isActive: true,
        emailVerified: false,
      });

      expect(result).not.toHaveProperty('password');
      expect(bcrypt.hash).toHaveBeenCalledWith(userData.password, 12);
      expect(mockClient.put).toHaveBeenCalled();
    });

    it('should throw ConflictError if email already exists', async () => {
      // Mock query to return existing user
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [{ id: 'existing-user', email: userData.email }],
        }),
      });

      await expect(userDb.createUser(userData)).rejects.toThrow(ConflictError);
      expect(mockClient.put).not.toHaveBeenCalled();
    });

    it('should handle database errors', async () => {
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Items: [] }),
      });

      bcrypt.hash.mockResolvedValue('hashedpassword');

      mockClient.put.mockReturnValue({
        promise: jest.fn().mockRejectedValue(new Error('Database error')),
      });

      await expect(userDb.createUser(userData)).rejects.toThrow('Failed to create user');
    });
  });

  describe('findByEmail', () => {
    const email = 'test@example.com';
    const mockUser = {
      id: 'user-123',
      email: email.toLowerCase(),
      password: 'hashedpassword',
      firstName: 'John',
      lastName: 'Doe',
    };

    it('should find user by email', async () => {
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [mockUser],
        }),
      });

      const result = await userDb.findByEmail(email);

      expect(result).toMatchObject({
        id: mockUser.id,
        email: mockUser.email,
        firstName: mockUser.firstName,
        lastName: mockUser.lastName,
      });

      expect(result).not.toHaveProperty('password');
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.objectContaining({
          IndexName: 'email-index',
        })
      );
    });

    it('should include password when requested', async () => {
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [mockUser],
        }),
      });

      const result = await userDb.findByEmail(email, true);

      expect(result).toHaveProperty('password', mockUser.password);
    });

    it('should return null if user not found', async () => {
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [],
        }),
      });

      const result = await userDb.findByEmail(email);

      expect(result).toBeNull();
    });

    it('should handle case insensitive email search', async () => {
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [mockUser],
        }),
      });

      await userDb.findByEmail('TEST@EXAMPLE.COM');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('#email = :email'),
        expect.objectContaining({
          expressionAttributeValues: {
            ':email': email.toLowerCase(),
          },
        })
      );
    });
  });

  describe('authenticateUser', () => {
    const email = 'test@example.com';
    const password = 'password123';
    const mockUser = {
      id: 'user-123',
      email,
      password: 'hashedpassword',
      firstName: 'John',
      lastName: 'Doe',
      isActive: true,
      loginAttempts: 0,
      lockedUntil: null,
    };

    it('should authenticate user successfully', async () => {
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [mockUser],
        }),
      });

      bcrypt.compare.mockResolvedValue(true);

      mockClient.update.mockReturnValue({
        promise: jest.fn().mockResolvedValue({}),
      });

      const result = await userDb.authenticateUser(email, password);

      expect(result).toMatchObject({
        id: mockUser.id,
        email: mockUser.email,
        firstName: mockUser.firstName,
        lastName: mockUser.lastName,
      });

      expect(result).not.toHaveProperty('password');
      expect(bcrypt.compare).toHaveBeenCalledWith(password, mockUser.password);
      expect(mockClient.update).toHaveBeenCalled(); // Updates lastLoginAt
    });

    it('should throw NotFoundError for non-existent user', async () => {
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [],
        }),
      });

      await expect(userDb.authenticateUser(email, password)).rejects.toThrow(NotFoundError);
      expect(bcrypt.compare).not.toHaveBeenCalled();
    });

    it('should throw NotFoundError for invalid password', async () => {
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [mockUser],
        }),
      });

      bcrypt.compare.mockResolvedValue(false);

      // Mock update for incrementing login attempts
      mockClient.get.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Item: mockUser }),
      });

      mockClient.update.mockReturnValue({
        promise: jest.fn().mockResolvedValue({}),
      });

      await expect(userDb.authenticateUser(email, password)).rejects.toThrow(NotFoundError);
      expect(bcrypt.compare).toHaveBeenCalledWith(password, mockUser.password);
    });

    it('should throw error for locked account', async () => {
      const lockedUser = {
        ...mockUser,
        lockedUntil: new Date(Date.now() + 30 * 60 * 1000).toISOString(), // 30 minutes from now
      };

      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [lockedUser],
        }),
      });

      await expect(userDb.authenticateUser(email, password)).rejects.toThrow(/locked/);
      expect(bcrypt.compare).not.toHaveBeenCalled();
    });

    it('should throw error for inactive account', async () => {
      const inactiveUser = {
        ...mockUser,
        isActive: false,
      };

      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [inactiveUser],
        }),
      });

      await expect(userDb.authenticateUser(email, password)).rejects.toThrow(/deactivated/);
      expect(bcrypt.compare).not.toHaveBeenCalled();
    });
  });

  describe('updatePassword', () => {
    const userId = 'user-123';
    const currentPassword = 'oldpassword';
    const newPassword = 'newpassword';
    const mockUser = {
      id: userId,
      email: 'test@example.com',
      password: 'hashedoldpassword',
    };

    it('should update password successfully', async () => {
      // Mock get user
      mockClient.get.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Item: mockUser }),
      });

      // Mock query for email lookup
      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [mockUser],
        }),
      });

      // Mock password verification
      bcrypt.compare.mockResolvedValue(true);

      // Mock password hashing
      bcrypt.hash.mockResolvedValue('hashednewpassword');

      // Mock update
      mockClient.update.mockReturnValue({
        promise: jest.fn().mockResolvedValue({}),
      });

      const result = await userDb.updatePassword(userId, currentPassword, newPassword);

      expect(result).toEqual({ message: 'Password updated successfully' });
      expect(bcrypt.compare).toHaveBeenCalledWith(currentPassword, mockUser.password);
      expect(bcrypt.hash).toHaveBeenCalledWith(newPassword, 12);
      expect(mockClient.update).toHaveBeenCalled();
    });

    it('should throw NotFoundError for non-existent user', async () => {
      mockClient.get.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Item: null }),
      });

      await expect(userDb.updatePassword(userId, currentPassword, newPassword))
        .rejects.toThrow(NotFoundError);
    });

    it('should throw error for incorrect current password', async () => {
      mockClient.get.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Item: mockUser }),
      });

      mockClient.query.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [mockUser],
        }),
      });

      bcrypt.compare.mockResolvedValue(false);

      await expect(userDb.updatePassword(userId, currentPassword, newPassword))
        .rejects.toThrow(/incorrect/);
    });
  });

  describe('getUserProfile', () => {
    const userId = 'user-123';
    const mockUser = {
      id: userId,
      email: 'test@example.com',
      firstName: 'John',
      lastName: 'Doe',
      password: 'hashedpassword',
      loginAttempts: 0,
      lockedUntil: null,
      metadata: { registrationIp: '127.0.0.1' },
    };

    it('should return user profile without sensitive data', async () => {
      mockClient.get.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Item: mockUser }),
      });

      const result = await userDb.getUserProfile(userId);

      expect(result).toMatchObject({
        id: mockUser.id,
        email: mockUser.email,
        firstName: mockUser.firstName,
        lastName: mockUser.lastName,
      });

      expect(result).not.toHaveProperty('password');
      expect(result).not.toHaveProperty('loginAttempts');
      expect(result).not.toHaveProperty('lockedUntil');
      expect(result).not.toHaveProperty('metadata');
    });

    it('should throw NotFoundError for non-existent user', async () => {
      mockClient.get.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Item: null }),
      });

      await expect(userDb.getUserProfile(userId)).rejects.toThrow(NotFoundError);
    });
  });

  describe('incrementLoginAttempts', () => {
    const userId = 'user-123';
    const mockUser = {
      id: userId,
      loginAttempts: 2,
    };

    it('should increment login attempts', async () => {
      mockClient.get.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Item: mockUser }),
      });

      mockClient.update.mockReturnValue({
        promise: jest.fn().mockResolvedValue({}),
      });

      await userDb.incrementLoginAttempts(userId);

      expect(mockClient.update).toHaveBeenCalledWith(
        expect.objectContaining({
          UpdateExpression: expect.stringContaining('loginAttempts'),
          ExpressionAttributeValues: expect.objectContaining({
            ':val0': 3,
          }),
        })
      );
    });

    it('should lock account after max attempts', async () => {
      const userWithManyAttempts = {
        id: userId,
        loginAttempts: 4, // Next attempt will be 5 (max)
      };

      mockClient.get.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Item: userWithManyAttempts }),
      });

      mockClient.update.mockReturnValue({
        promise: jest.fn().mockResolvedValue({}),
      });

      await userDb.incrementLoginAttempts(userId);

      expect(mockClient.update).toHaveBeenCalledWith(
        expect.objectContaining({
          ExpressionAttributeValues: expect.objectContaining({
            ':val0': 5, // attempts
            ':val1': expect.any(String), // lockedUntil timestamp
          }),
        })
      );
    });

    it('should handle missing user gracefully', async () => {
      mockClient.get.mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Item: null }),
      });

      await expect(userDb.incrementLoginAttempts(userId)).resolves.toBeUndefined();
      expect(mockClient.update).not.toHaveBeenCalled();
    });
  });

  describe('healthCheck', () => {
    it('should return healthy status', async () => {
      mockClient.scan.mockReturnValue({
        promise: jest.fn().mockResolvedValue({
          Items: [],
          ScannedCount: 5,
        }),
      });

      const result = await userDb.healthCheck();

      expect(result).toMatchObject({
        status: 'healthy',
        table: expect.any(String),
        userCount: 5,
        indexes: ['email-index'],
      });
    });

    it('should return unhealthy status on error', async () => {
      mockClient.scan.mockReturnValue({
        promise: jest.fn().mockRejectedValue(new Error('Connection failed')),
      });

      const result = await userDb.healthCheck();

      expect(result).toMatchObject({
        status: 'unhealthy',
        table: expect.any(String),
        error: 'Connection failed',
      });
    });
  });
});