const express = require('express');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { CloudWatchClient } = require('@aws-sdk/client-cloudwatch');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const config = require('../config');
const logger = require('../utils/logger');

const router = express.Router();

// Initialize AWS clients
const dynamoClient = new DynamoDBClient({ region: config.aws.region });
const cloudWatchClient = new CloudWatchClient({ region: config.aws.region });
const secretsClient = new SecretsManagerClient({ region: config.aws.region });

// Health check cache
let healthCache = {
  status: 'unknown',
  lastCheck: 0,
  details: {},
};

const CACHE_TTL = 30000; // 30 seconds

// Helper function to check DynamoDB health
async function checkDynamoDB() {
  try {
    const command = {
      TableName: config.database.tableName,
    };
    
    // Simple describe table operation
    await dynamoClient.send(new (require('@aws-sdk/client-dynamodb').DescribeTableCommand)(command));
    
    return {
      status: 'healthy',
      message: 'DynamoDB connection successful',
      responseTime: Date.now(),
    };
  } catch (error) {
    logger.error('DynamoDB health check failed:', error);
    return {
      status: 'unhealthy',
      message: error.message,
      error: error.code || 'UNKNOWN_ERROR',
    };
  }
}

// Helper function to check Secrets Manager health
async function checkSecretsManager() {
  try {
    const command = new GetSecretValueCommand({
      SecretId: config.secrets.secretName,
    });
    
    await secretsClient.send(command);
    
    return {
      status: 'healthy',
      message: 'Secrets Manager connection successful',
      responseTime: Date.now(),
    };
  } catch (error) {
    logger.error('Secrets Manager health check failed:', error);
    return {
      status: 'unhealthy',
      message: error.message,
      error: error.code || 'UNKNOWN_ERROR',
    };
  }
}

// Helper function to check system resources
function checkSystemResources() {
  const memUsage = process.memoryUsage();
  const cpuUsage = process.cpuUsage();
  
  return {
    status: 'healthy',
    memory: {
      used: Math.round(memUsage.heapUsed / 1024 / 1024),
      total: Math.round(memUsage.heapTotal / 1024 / 1024),
      external: Math.round(memUsage.external / 1024 / 1024),
      rss: Math.round(memUsage.rss / 1024 / 1024),
    },
    cpu: {
      user: cpuUsage.user,
      system: cpuUsage.system,
    },
    uptime: Math.round(process.uptime()),
    pid: process.pid,
  };
}

// Liveness probe - simple endpoint that returns 200 if service is running
router.get('/live', (req, res) => {
  res.status(200).json({
    status: 'alive',
    timestamp: new Date().toISOString(),
    service: config.app.name,
    version: config.app.version,
  });
});

// Readiness probe - checks if service is ready to handle requests
router.get('/ready', async (req, res) => {
  try {
    const now = Date.now();
    
    // Use cached result if recent
    if (now - healthCache.lastCheck < CACHE_TTL && healthCache.status !== 'unknown') {
      return res.status(healthCache.status === 'healthy' ? 200 : 503).json({
        status: healthCache.status,
        timestamp: new Date(healthCache.lastCheck).toISOString(),
        cached: true,
        details: healthCache.details,
      });
    }

    // Perform health checks
    const [dynamoHealth, secretsHealth] = await Promise.allSettled([
      checkDynamoDB(),
      checkSecretsManager(),
    ]);

    const systemHealth = checkSystemResources();

    const details = {
      database: dynamoHealth.status === 'fulfilled' ? dynamoHealth.value : dynamoHealth.reason,
      secrets: secretsHealth.status === 'fulfilled' ? secretsHealth.value : secretsHealth.reason,
      system: systemHealth,
    };

    // Determine overall health
    const isHealthy = dynamoHealth.status === 'fulfilled' && 
                     dynamoHealth.value.status === 'healthy' &&
                     secretsHealth.status === 'fulfilled' && 
                     secretsHealth.value.status === 'healthy';

    const status = isHealthy ? 'healthy' : 'unhealthy';

    // Update cache
    healthCache = {
      status,
      lastCheck: now,
      details,
    };

    res.status(isHealthy ? 200 : 503).json({
      status,
      timestamp: new Date().toISOString(),
      cached: false,
      details,
    });

  } catch (error) {
    logger.error('Health check failed:', error);
    
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message,
    });
  }
});

// Comprehensive health endpoint
router.get('/', async (req, res) => {
  try {
    const startTime = Date.now();

    // Perform all health checks
    const [dynamoHealth, secretsHealth] = await Promise.allSettled([
      checkDynamoDB(),
      checkSecretsManager(),
    ]);

    const systemHealth = checkSystemResources();
    const responseTime = Date.now() - startTime;

    const details = {
      database: dynamoHealth.status === 'fulfilled' ? dynamoHealth.value : {
        status: 'unhealthy',
        error: dynamoHealth.reason?.message || 'Unknown error',
      },
      secrets: secretsHealth.status === 'fulfilled' ? secretsHealth.value : {
        status: 'unhealthy',
        error: secretsHealth.reason?.message || 'Unknown error',
      },
      system: systemHealth,
    };

    // Determine overall health
    const healthyServices = Object.values(details).filter(
      service => service.status === 'healthy'
    ).length;
    const totalServices = Object.keys(details).length;

    const overallStatus = healthyServices === totalServices ? 'healthy' : 
                         healthyServices > 0 ? 'degraded' : 'unhealthy';

    const healthData = {
      status: overallStatus,
      timestamp: new Date().toISOString(),
      service: config.app.name,
      version: config.app.version,
      environment: config.environment,
      region: config.aws.region,
      responseTime: `${responseTime}ms`,
      checks: {
        total: totalServices,
        healthy: healthyServices,
        unhealthy: totalServices - healthyServices,
      },
      details,
    };

    // Set appropriate status code
    const statusCode = overallStatus === 'healthy' ? 200 :
                      overallStatus === 'degraded' ? 200 : 503;

    res.status(statusCode).json(healthData);

  } catch (error) {
    logger.error('Comprehensive health check failed:', error);
    
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      service: config.app.name,
      version: config.app.version,
      error: error.message,
    });
  }
});

module.exports = router;