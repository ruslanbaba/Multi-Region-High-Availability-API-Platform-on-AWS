# API Service

A production-ready, scalable API service built with Node.js and Express, designed for multi-region deployment on AWS. This service demonstrates enterprise-grade patterns including comprehensive security, monitoring, caching, and database operations.

## Features

### 🔐 Security
- JWT-based authentication with refresh tokens
- Password hashing with bcrypt (12 rounds)
- Rate limiting and request throttling
- CORS protection with configurable origins
- Security headers (helmet.js)
- Input validation and sanitization
- API key authentication for service-to-service communication

### 📊 Monitoring & Observability
- Structured logging with Pino
- Prometheus metrics integration
- AWS CloudWatch metrics and logs
- Health check endpoints (liveness, readiness, full health)
- Request tracing and error tracking
- Performance monitoring

### 💾 Data Management
- DynamoDB integration with AWS SDK v3
- In-memory caching with NodeCache
- Database connection pooling
- Automatic retry logic with exponential backoff
- Data validation and sanitization

### 🚀 Performance
- Compression middleware
- Response caching
- Database query optimization
- Graceful shutdown handling
- Memory usage monitoring

### 🧪 Testing
- Comprehensive test suite with Jest
- Unit tests, integration tests
- Test coverage reporting
- Mock implementations for external services

## Quick Start

### Prerequisites
- Node.js 18+ 
- npm or yarn
- AWS account (for DynamoDB)
- Docker (optional, for containerized deployment)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd applications/api-service
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Start the development server**
   ```bash
   npm run dev
   ```

The API will be available at `http://localhost:3000`

### Environment Configuration

Create a `.env` file with the following variables:

```env
# Server Configuration
NODE_ENV=development
PORT=3000
LOG_LEVEL=info

# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key

# Database Configuration
DYNAMODB_USER_TABLE=users

# JWT Configuration
JWT_SECRET=your-super-secret-jwt-key
JWT_REFRESH_SECRET=your-super-secret-refresh-key
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# Auth Configuration
API_KEY=your-api-key-for-service-auth

# Cache Configuration
CACHE_TTL=3600
CACHE_CHECK_PERIOD=600

# Service Configuration
SERVICE_NAME=api-service
SERVICE_VERSION=1.0.0
```

## API Documentation

### Health Endpoints

#### Liveness Probe
```http
GET /health/liveness
```
Basic health check to verify the service is running.

#### Readiness Probe
```http
GET /health/readiness
```
Comprehensive health check including database and cache connectivity.

#### Full Health Check
```http
GET /health
```
Detailed health information including system metrics and dependency status.

### User Management

#### Register User
```http
POST /api/v1/users/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "SecurePassword123!",
  "firstName": "John",
  "lastName": "Doe"
}
```

#### Login
```http
POST /api/v1/users/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "SecurePassword123!"
}
```

#### Get User Profile
```http
GET /api/v1/users/profile
Authorization: Bearer <jwt-token>
```

#### Update User Profile
```http
PUT /api/v1/users/profile
Authorization: Bearer <jwt-token>
Content-Type: application/json

{
  "firstName": "Jane",
  "lastName": "Smith"
}
```

#### Change Password
```http
PUT /api/v1/users/password
Authorization: Bearer <jwt-token>
Content-Type: application/json

{
  "currentPassword": "CurrentPassword123!",
  "newPassword": "NewPassword123!"
}
```

### Admin Endpoints

#### List Users (Admin Only)
```http
GET /api/v1/users?page=1&limit=10&search=john
Authorization: Bearer <admin-jwt-token>
```

#### Get User by ID (Admin or Self)
```http
GET /api/v1/users/:id
Authorization: Bearer <jwt-token>
```

#### Delete User (Admin Only)
```http
DELETE /api/v1/users/:id
Authorization: Bearer <admin-jwt-token>
```

## Development

### Project Structure

```
src/
├── app.js              # Express application setup
├── server.js           # Server entry point
├── config/             # Configuration management
│   └── index.js
├── middleware/         # Custom middleware
│   ├── auth.js         # Authentication middleware
│   ├── errorHandler.js # Error handling middleware
│   └── validation.js   # Request validation middleware
├── routes/             # API route definitions
│   ├── health.js       # Health check routes
│   └── users.js        # User management routes
├── db/                 # Database layer
│   ├── base.js         # Base database class
│   └── users.js        # User database operations
└── utils/              # Utility modules
    ├── logger.js       # Logging configuration
    ├── metrics.js      # Metrics collection
    └── cache.js        # Caching utilities

tests/                  # Test files
├── setup.js           # Test setup configuration
├── globalSetup.js     # Global test setup
├── globalTeardown.js  # Global test teardown
├── health.test.js     # Health endpoint tests
├── users.test.js      # User route tests
└── database.test.js   # Database operation tests
```

### Available Scripts

```bash
# Development
npm run dev          # Start development server with nodemon
npm start           # Start production server

# Testing
npm test            # Run all tests
npm run test:watch  # Run tests in watch mode
npm run test:coverage # Run tests with coverage report

# Code Quality
npm run lint        # Run ESLint
npm run lint:fix    # Fix ESLint issues
npm run format      # Format code with Prettier

# Production
npm run build       # Build for production (if applicable)
npm run docker:build # Build Docker image
npm run docker:run  # Run Docker container
```

### Docker Deployment

#### Build Docker Image
```bash
docker build -t api-service .
```

#### Run Container
```bash
docker run -p 3000:3000 \
  -e NODE_ENV=production \
  -e AWS_REGION=us-east-1 \
  -e JWT_SECRET=your-secret \
  api-service
```

#### Docker Compose
```yaml
version: '3.8'
services:
  api:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - AWS_REGION=us-east-1
      - JWT_SECRET=your-secret
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health/liveness"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## Testing

### Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run specific test file
npm test -- users.test.js

# Run tests with coverage
npm run test:coverage
```

### Test Coverage

The project maintains high test coverage:
- Statements: >80%
- Branches: >80%
- Functions: >80%
- Lines: >80%

### Test Types

1. **Unit Tests**: Individual function and class testing
2. **Integration Tests**: API endpoint testing with mocked dependencies
3. **Health Check Tests**: Service health and monitoring validation

## Monitoring

### Metrics Collection

The service exposes Prometheus-compatible metrics:

- HTTP request duration and count
- Database operation metrics
- Cache hit/miss ratios
- Error rates and types
- System resource usage

### Logging

Structured logging with configurable levels:

```javascript
// Log levels: trace, debug, info, warn, error, fatal
logger.info({ userId: '123', action: 'login' }, 'User logged in successfully');
```

### Health Checks

Three levels of health checks:

1. **Liveness**: Basic service availability
2. **Readiness**: Service ready to handle requests
3. **Full Health**: Comprehensive system status including dependencies

## Security

### Authentication Flow

1. User registers with email/password
2. Password is hashed with bcrypt (12 rounds)
3. User logs in to receive JWT access token and refresh token
4. Access token used for API requests (15-minute expiry)
5. Refresh token used to obtain new access tokens (7-day expiry)

### Security Headers

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Strict-Transport-Security` (HTTPS only)

### Rate Limiting

- Authentication endpoints: 5 requests per minute
- General API: 100 requests per minute
- Admin endpoints: 20 requests per minute

## Deployment

### AWS ECS Deployment

This service is designed for deployment on AWS ECS Fargate:

1. **Container Registry**: Push image to AWS ECR
2. **Task Definition**: Configure ECS task with environment variables
3. **Service**: Deploy with load balancer integration
4. **Auto Scaling**: Configure based on CPU/memory metrics

### Environment-Specific Configuration

- **Development**: Local DynamoDB, verbose logging
- **Staging**: AWS services, moderate logging
- **Production**: Full AWS integration, minimal logging

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow ESLint and Prettier configurations
- Write tests for new features
- Update documentation for API changes
- Use conventional commit messages
- Ensure all tests pass before submitting PR

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support and questions:
- Create an issue in the repository
- Check the documentation
- Review the test files for usage examples

---

Built with ❤️ for enterprise-grade applications