const promClient = require('prom-client');
const { CloudWatchClient, PutMetricDataCommand } = require('@aws-sdk/client-cloudwatch');
const config = require('../config');
const logger = require('./logger');

// Initialize CloudWatch client
const cloudWatchClient = new CloudWatchClient({ region: config.aws.region });

// Custom metrics registry
const register = new promClient.Registry();

// Default metrics
promClient.collectDefaultMetrics({ register });

// Custom application metrics
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10],
  registers: [register],
});

const httpRequestTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const dbOperationDuration = new promClient.Histogram({
  name: 'db_operation_duration_seconds',
  help: 'Duration of database operations in seconds',
  labelNames: ['operation', 'table'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 3, 5],
  registers: [register],
});

const dbOperationTotal = new promClient.Counter({
  name: 'db_operations_total',
  help: 'Total number of database operations',
  labelNames: ['operation', 'table', 'status'],
  registers: [register],
});

const activeConnections = new promClient.Gauge({
  name: 'active_connections',
  help: 'Number of active connections',
  registers: [register],
});

const businessMetrics = new promClient.Counter({
  name: 'business_events_total',
  help: 'Total number of business events',
  labelNames: ['event_type', 'status'],
  registers: [register],
});

const errorCounter = new promClient.Counter({
  name: 'application_errors_total',
  help: 'Total number of application errors',
  labelNames: ['error_type', 'component'],
  registers: [register],
});

const cacheHits = new promClient.Counter({
  name: 'cache_hits_total',
  help: 'Total number of cache hits',
  labelNames: ['cache_type'],
  registers: [register],
});

const cacheMisses = new promClient.Counter({
  name: 'cache_misses_total',
  help: 'Total number of cache misses',
  labelNames: ['cache_type'],
  registers: [register],
});

// Initialize metrics collection
function initializeMetrics() {
  logger.info('Initializing metrics collection');
  
  // Set initial values
  activeConnections.set(0);
  
  // Collect and send metrics to CloudWatch every 60 seconds
  if (config.metrics.enabled) {
    setInterval(sendMetricsToCloudWatch, 60000);
  }
}

// Send metrics to CloudWatch
async function sendMetricsToCloudWatch() {
  try {
    const metrics = await register.metrics();
    const metricLines = metrics.split('\n').filter(line => 
      !line.startsWith('#') && line.trim() !== ''
    );

    const metricData = [];

    for (const line of metricLines) {
      const [metricName, value] = line.split(' ');
      if (metricName && value && !isNaN(value)) {
        metricData.push({
          MetricName: metricName.replace(/[^a-zA-Z0-9_]/g, '_'),
          Value: parseFloat(value),
          Unit: 'Count',
          Timestamp: new Date(),
          Dimensions: [
            {
              Name: 'Service',
              Value: config.app.name,
            },
            {
              Name: 'Environment',
              Value: config.environment,
            },
            {
              Name: 'Region',
              Value: config.aws.region,
            },
          ],
        });
      }
    }

    if (metricData.length > 0) {
      const command = new PutMetricDataCommand({
        Namespace: config.metrics.namespace,
        MetricData: metricData.slice(0, 20), // CloudWatch limit
      });

      await cloudWatchClient.send(command);
      logger.debug(`Sent ${metricData.length} metrics to CloudWatch`);
    }
  } catch (error) {
    logger.error('Failed to send metrics to CloudWatch:', error);
  }
}

// Record custom metric
function recordMetric(metricName, value = 1, labels = {}) {
  try {
    businessMetrics.inc({ event_type: metricName, status: 'success', ...labels }, value);
    
    // Also send to CloudWatch immediately for important metrics
    if (config.metrics.enabled) {
      sendSingleMetricToCloudWatch(metricName, value, labels);
    }
  } catch (error) {
    logger.error('Failed to record metric:', error);
  }
}

// Send single metric to CloudWatch
async function sendSingleMetricToCloudWatch(metricName, value, labels = {}) {
  try {
    const dimensions = [
      {
        Name: 'Service',
        Value: config.app.name,
      },
      {
        Name: 'Environment',
        Value: config.environment,
      },
      {
        Name: 'Region',
        Value: config.aws.region,
      },
      ...Object.entries(labels).map(([key, val]) => ({
        Name: key,
        Value: String(val),
      })),
    ];

    const command = new PutMetricDataCommand({
      Namespace: config.metrics.namespace,
      MetricData: [
        {
          MetricName: metricName,
          Value: value,
          Unit: 'Count',
          Timestamp: new Date(),
          Dimensions: dimensions,
        },
      ],
    });

    await cloudWatchClient.send(command);
  } catch (error) {
    logger.error('Failed to send single metric to CloudWatch:', error);
  }
}

// Record HTTP request metrics
function recordHttpRequest(req, res, duration) {
  const labels = {
    method: req.method,
    route: req.route?.path || req.path,
    status_code: res.statusCode,
  };

  httpRequestDuration.observe(labels, duration / 1000);
  httpRequestTotal.inc(labels);
}

// Record database operation metrics
function recordDbOperation(operation, table, duration, status = 'success') {
  const labels = { operation, table, status };
  
  dbOperationDuration.observe({ operation, table }, duration / 1000);
  dbOperationTotal.inc(labels);
}

// Record error metrics
function recordError(errorType, component) {
  errorCounter.inc({ error_type: errorType, component });
}

// Record cache metrics
function recordCacheHit(cacheType) {
  cacheHits.inc({ cache_type: cacheType });
}

function recordCacheMiss(cacheType) {
  cacheMisses.inc({ cache_type: cacheType });
}

// Get metrics for Prometheus endpoint
function getMetrics() {
  return register.metrics();
}

module.exports = {
  initializeMetrics,
  recordMetric,
  recordHttpRequest,
  recordDbOperation,
  recordError,
  recordCacheHit,
  recordCacheMiss,
  getMetrics,
  register,
  // Individual metric objects for direct use
  httpRequestDuration,
  httpRequestTotal,
  dbOperationDuration,
  dbOperationTotal,
  activeConnections,
  businessMetrics,
  errorCounter,
  cacheHits,
  cacheMisses,
};