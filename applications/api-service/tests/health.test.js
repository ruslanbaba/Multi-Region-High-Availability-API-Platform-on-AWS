const request = require('supertest');
const app = require('../src/app');
const config = require('../src/config');

describe('Health Routes', () => {
  describe('GET /health/liveness', () => {
    it('should return 200 and liveness status', async () => {
      const response = await request(app)
        .get('/health/liveness')
        .expect(200);

      expect(response.body).toMatchObject({
        status: 'alive',
        timestamp: expect.any(String),
        service: config.service.name,
        version: config.service.version,
      });
    });
  });

  describe('GET /health/readiness', () => {
    it('should return 200 and readiness status', async () => {
      const response = await request(app)
        .get('/health/readiness')
        .expect(200);

      expect(response.body).toMatchObject({
        status: 'ready',
        timestamp: expect.any(String),
        service: config.service.name,
        version: config.service.version,
        checks: expect.objectContaining({
          database: expect.any(Object),
          cache: expect.any(Object),
        }),
      });
    });

    it('should include database and cache health checks', async () => {
      const response = await request(app)
        .get('/health/readiness')
        .expect(200);

      expect(response.body.checks.database).toHaveProperty('status');
      expect(response.body.checks.cache).toHaveProperty('status');
    });
  });

  describe('GET /health', () => {
    it('should return comprehensive health information', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body).toMatchObject({
        status: expect.stringMatching(/^(healthy|degraded|unhealthy)$/),
        timestamp: expect.any(String),
        service: expect.objectContaining({
          name: config.service.name,
          version: config.service.version,
          environment: config.nodeEnv,
        }),
        system: expect.objectContaining({
          uptime: expect.any(Number),
          memory: expect.any(Object),
          cpu: expect.any(Object),
        }),
        dependencies: expect.objectContaining({
          database: expect.any(Object),
          cache: expect.any(Object),
        }),
      });
    });

    it('should include system information', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.body.system.memory).toHaveProperty('used');
      expect(response.body.system.memory).toHaveProperty('total');
      expect(response.body.system.memory).toHaveProperty('percentage');
    });
  });
});

describe('API Routes', () => {
  describe('GET /api/v1/health/liveness', () => {
    it('should return liveness status through API prefix', async () => {
      const response = await request(app)
        .get('/api/v1/health/liveness')
        .expect(200);

      expect(response.body.status).toBe('alive');
    });
  });

  describe('GET /api/v1/health/readiness', () => {
    it('should return readiness status through API prefix', async () => {
      const response = await request(app)
        .get('/api/v1/health/readiness')
        .expect(200);

      expect(response.body.status).toBe('ready');
    });
  });
});

describe('Error Handling', () => {
  it('should return 404 for non-existent routes', async () => {
    const response = await request(app)
      .get('/non-existent-route')
      .expect(404);

    expect(response.body).toMatchObject({
      error: expect.any(String),
      timestamp: expect.any(String),
      path: '/non-existent-route',
      method: 'GET',
    });
  });

  it('should handle malformed requests gracefully', async () => {
    const response = await request(app)
      .get('/health?invalid=query&')
      .expect(200);

    // Should still return health data despite malformed query
    expect(response.body).toHaveProperty('status');
  });
});

describe('CORS Headers', () => {
  it('should include CORS headers in health responses', async () => {
    const response = await request(app)
      .get('/health/liveness')
      .expect(200);

    expect(response.headers).toHaveProperty('access-control-allow-origin');
  });

  it('should handle OPTIONS requests for CORS preflight', async () => {
    await request(app)
      .options('/health/liveness')
      .expect(204);
  });
});

describe('Security Headers', () => {
  it('should include security headers', async () => {
    const response = await request(app)
      .get('/health/liveness')
      .expect(200);

    expect(response.headers).toHaveProperty('x-content-type-options', 'nosniff');
    expect(response.headers).toHaveProperty('x-frame-options', 'DENY');
    expect(response.headers).toHaveProperty('x-xss-protection', '1; mode=block');
  });
});

describe('Performance', () => {
  it('should respond to liveness checks quickly', async () => {
    const start = Date.now();
    
    await request(app)
      .get('/health/liveness')
      .expect(200);
    
    const duration = Date.now() - start;
    expect(duration).toBeLessThan(100); // Should respond within 100ms
  });

  it('should handle multiple concurrent health checks', async () => {
    const promises = Array(10).fill().map(() => 
      request(app).get('/health/liveness').expect(200)
    );

    const responses = await Promise.all(promises);
    
    responses.forEach(response => {
      expect(response.body.status).toBe('alive');
    });
  });
});