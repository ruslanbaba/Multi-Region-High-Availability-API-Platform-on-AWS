const request = require('supertest');
const app = require('../src/app');
const UserDatabase = require('../src/db/users');
const { generateToken } = require('../src/middleware/auth');

// Mock the database
jest.mock('../src/db/users');

describe('User Routes', () => {
  let userDb;
  let mockUser;
  let authToken;

  beforeEach(() => {
    userDb = new UserDatabase();
    UserDatabase.mockClear();

    mockUser = {
      id: 'user-123',
      email: 'test@example.com',
      firstName: 'John',
      lastName: 'Doe',
      roles: ['user'],
      isActive: true,
      emailVerified: true,
      createdAt: '2024-01-01T00:00:00.000Z',
      updatedAt: '2024-01-01T00:00:00.000Z',
    };

    authToken = generateToken(mockUser);
  });

  describe('POST /api/v1/users/register', () => {
    const validUserData = {
      email: 'newuser@example.com',
      password: 'Password123!',
      firstName: 'Jane',
      lastName: 'Smith',
    };

    it('should register a new user successfully', async () => {
      userDb.createUser.mockResolvedValue(mockUser);

      const response = await request(app)
        .post('/api/v1/users/register')
        .send(validUserData)
        .expect(201);

      expect(response.body).toMatchObject({
        message: 'User registered successfully',
        user: expect.objectContaining({
          id: expect.any(String),
          email: validUserData.email,
          firstName: validUserData.firstName,
          lastName: validUserData.lastName,
        }),
      });

      expect(response.body.user).not.toHaveProperty('password');
      expect(userDb.createUser).toHaveBeenCalledWith(
        expect.objectContaining(validUserData)
      );
    });

    it('should return 400 for invalid email', async () => {
      const invalidData = { ...validUserData, email: 'invalid-email' };

      const response = await request(app)
        .post('/api/v1/users/register')
        .send(invalidData)
        .expect(400);

      expect(response.body.error).toBe('Validation failed');
      expect(response.body.details).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            field: 'email',
            message: expect.stringContaining('valid email'),
          }),
        ])
      );
    });

    it('should return 400 for weak password', async () => {
      const invalidData = { ...validUserData, password: 'weak' };

      const response = await request(app)
        .post('/api/v1/users/register')
        .send(invalidData)
        .expect(400);

      expect(response.body.error).toBe('Validation failed');
      expect(response.body.details).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            field: 'password',
            message: expect.stringContaining('at least 8 characters'),
          }),
        ])
      );
    });

    it('should return 409 for duplicate email', async () => {
      userDb.createUser.mockRejectedValue(new Error('User with this email already exists'));

      await request(app)
        .post('/api/v1/users/register')
        .send(validUserData)
        .expect(409);
    });
  });

  describe('POST /api/v1/users/login', () => {
    const loginData = {
      email: 'test@example.com',
      password: 'Password123!',
    };

    it('should login user successfully', async () => {
      userDb.authenticateUser.mockResolvedValue(mockUser);

      const response = await request(app)
        .post('/api/v1/users/login')
        .send(loginData)
        .expect(200);

      expect(response.body).toMatchObject({
        message: 'Login successful',
        user: expect.objectContaining({
          id: mockUser.id,
          email: mockUser.email,
        }),
        token: expect.any(String),
        refreshToken: expect.any(String),
      });

      expect(userDb.authenticateUser).toHaveBeenCalledWith(
        loginData.email,
        loginData.password
      );
    });

    it('should return 401 for invalid credentials', async () => {
      userDb.authenticateUser.mockRejectedValue(new Error('Invalid email or password'));

      await request(app)
        .post('/api/v1/users/login')
        .send(loginData)
        .expect(401);
    });

    it('should return 400 for missing email', async () => {
      const invalidData = { password: 'Password123!' };

      const response = await request(app)
        .post('/api/v1/users/login')
        .send(invalidData)
        .expect(400);

      expect(response.body.error).toBe('Validation failed');
    });
  });

  describe('GET /api/v1/users/profile', () => {
    it('should get user profile successfully', async () => {
      userDb.getUserProfile.mockResolvedValue(mockUser);

      const response = await request(app)
        .get('/api/v1/users/profile')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      expect(response.body).toMatchObject({
        user: expect.objectContaining({
          id: mockUser.id,
          email: mockUser.email,
        }),
      });

      expect(userDb.getUserProfile).toHaveBeenCalledWith(mockUser.id);
    });

    it('should return 401 without authentication', async () => {
      await request(app)
        .get('/api/v1/users/profile')
        .expect(401);
    });

    it('should return 401 with invalid token', async () => {
      await request(app)
        .get('/api/v1/users/profile')
        .set('Authorization', 'Bearer invalid-token')
        .expect(401);
    });
  });

  describe('PUT /api/v1/users/profile', () => {
    const updateData = {
      firstName: 'Updated',
      lastName: 'Name',
    };

    it('should update user profile successfully', async () => {
      const updatedUser = { ...mockUser, ...updateData };
      userDb.updateUserProfile.mockResolvedValue(updatedUser);

      const response = await request(app)
        .put('/api/v1/users/profile')
        .set('Authorization', `Bearer ${authToken}`)
        .send(updateData)
        .expect(200);

      expect(response.body).toMatchObject({
        message: 'Profile updated successfully',
        user: expect.objectContaining(updateData),
      });

      expect(userDb.updateUserProfile).toHaveBeenCalledWith(
        mockUser.id,
        updateData
      );
    });

    it('should return 400 for invalid update data', async () => {
      const invalidData = { firstName: '' };

      const response = await request(app)
        .put('/api/v1/users/profile')
        .set('Authorization', `Bearer ${authToken}`)
        .send(invalidData)
        .expect(400);

      expect(response.body.error).toBe('Validation failed');
    });
  });

  describe('PUT /api/v1/users/password', () => {
    const passwordData = {
      currentPassword: 'OldPassword123!',
      newPassword: 'NewPassword123!',
    };

    it('should change password successfully', async () => {
      userDb.updatePassword.mockResolvedValue({ message: 'Password updated successfully' });

      const response = await request(app)
        .put('/api/v1/users/password')
        .set('Authorization', `Bearer ${authToken}`)
        .send(passwordData)
        .expect(200);

      expect(response.body.message).toBe('Password updated successfully');
      expect(userDb.updatePassword).toHaveBeenCalledWith(
        mockUser.id,
        passwordData.currentPassword,
        passwordData.newPassword
      );
    });

    it('should return 400 for weak new password', async () => {
      const invalidData = { ...passwordData, newPassword: 'weak' };

      const response = await request(app)
        .put('/api/v1/users/password')
        .set('Authorization', `Bearer ${authToken}`)
        .send(invalidData)
        .expect(400);

      expect(response.body.error).toBe('Validation failed');
    });
  });

  describe('GET /api/v1/users', () => {
    const adminUser = { ...mockUser, roles: ['admin'] };
    const adminToken = generateToken(adminUser);

    it('should get users list for admin', async () => {
      const usersResult = {
        items: [mockUser],
        count: 1,
        lastEvaluatedKey: null,
      };
      userDb.getUsers.mockResolvedValue(usersResult);

      const response = await request(app)
        .get('/api/v1/users')
        .set('Authorization', `Bearer ${adminToken}`)
        .expect(200);

      expect(response.body).toMatchObject({
        users: [expect.objectContaining({ id: mockUser.id })],
        pagination: expect.objectContaining({
          count: 1,
          hasMore: false,
        }),
      });
    });

    it('should return 403 for non-admin users', async () => {
      await request(app)
        .get('/api/v1/users')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(403);
    });

    it('should support pagination parameters', async () => {
      const usersResult = {
        items: [mockUser],
        count: 1,
        lastEvaluatedKey: null,
      };
      userDb.getUsers.mockResolvedValue(usersResult);

      await request(app)
        .get('/api/v1/users?page=2&limit=5')
        .set('Authorization', `Bearer ${adminToken}`)
        .expect(200);

      expect(userDb.getUsers).toHaveBeenCalledWith(
        expect.objectContaining({
          limit: 5,
        })
      );
    });
  });

  describe('GET /api/v1/users/:id', () => {
    const adminUser = { ...mockUser, roles: ['admin'] };
    const adminToken = generateToken(adminUser);

    it('should get user by ID for admin', async () => {
      userDb.getUserProfile.mockResolvedValue(mockUser);

      const response = await request(app)
        .get(`/api/v1/users/${mockUser.id}`)
        .set('Authorization', `Bearer ${adminToken}`)
        .expect(200);

      expect(response.body.user.id).toBe(mockUser.id);
    });

    it('should allow users to get their own profile', async () => {
      userDb.getUserProfile.mockResolvedValue(mockUser);

      const response = await request(app)
        .get(`/api/v1/users/${mockUser.id}`)
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200);

      expect(response.body.user.id).toBe(mockUser.id);
    });

    it('should return 403 for accessing other users profile', async () => {
      await request(app)
        .get('/api/v1/users/other-user-id')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(403);
    });

    it('should return 404 for non-existent user', async () => {
      userDb.getUserProfile.mockRejectedValue(new Error('User not found'));

      await request(app)
        .get('/api/v1/users/non-existent-id')
        .set('Authorization', `Bearer ${adminToken}`)
        .expect(404);
    });
  });

  describe('Rate Limiting', () => {
    it('should apply rate limiting to sensitive endpoints', async () => {
      // Make multiple rapid requests to login endpoint
      const promises = Array(10).fill().map(() =>
        request(app)
          .post('/api/v1/users/login')
          .send({
            email: 'test@example.com',
            password: 'wrong-password',
          })
      );

      const responses = await Promise.all(promises);
      
      // Some requests should be rate limited
      const rateLimitedResponses = responses.filter(res => res.status === 429);
      expect(rateLimitedResponses.length).toBeGreaterThan(0);
    });
  });
});