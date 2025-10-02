const NodeCache = require('node-cache');
const config = require('../config');
const logger = require('./logger');
const { recordCacheHit, recordCacheMiss } = require('./metrics');

// Initialize cache with configuration
const cache = new NodeCache({
  stdTTL: config.cache.ttl,
  checkperiod: config.cache.checkPeriod,
  useClones: false, // Better performance
});

// Cache events for logging and metrics
cache.on('set', (key, value) => {
  logger.debug({ key, valueType: typeof value }, 'Cache set');
});

cache.on('get', (key, value) => {
  if (value !== undefined) {
    recordCacheHit('application');
    logger.debug({ key }, 'Cache hit');
  }
});

cache.on('expired', (key, value) => {
  logger.debug({ key }, 'Cache key expired');
});

cache.on('del', (key) => {
  logger.debug({ key }, 'Cache key deleted');
});

// Wrapper functions with metrics
const cacheWrapper = {
  get: (key) => {
    const value = cache.get(key);
    if (value === undefined) {
      recordCacheMiss('application');
      logger.debug({ key }, 'Cache miss');
    }
    return value;
  },

  set: (key, value, ttl) => {
    return cache.set(key, value, ttl);
  },

  del: (key) => {
    return cache.del(key);
  },

  has: (key) => {
    return cache.has(key);
  },

  keys: () => {
    return cache.keys();
  },

  getStats: () => {
    return cache.getStats();
  },

  flushAll: () => {
    logger.info('Flushing all cache entries');
    return cache.flushAll();
  },

  close: () => {
    return cache.close();
  },

  // Get multiple keys at once
  mget: (keys) => {
    const result = {};
    keys.forEach(key => {
      result[key] = cacheWrapper.get(key);
    });
    return result;
  },

  // Set multiple keys at once
  mset: (keyValuePairs, ttl) => {
    const results = [];
    keyValuePairs.forEach(({ key, value, ttl: itemTtl }) => {
      results.push(cache.set(key, value, itemTtl || ttl));
    });
    return results;
  },

  // Delete multiple keys at once
  mdel: (keys) => {
    return cache.del(keys);
  },

  // Get cache info for health checks
  getInfo: () => {
    const stats = cache.getStats();
    return {
      keys: stats.keys,
      hits: stats.hits,
      misses: stats.misses,
      hitRate: stats.hits / (stats.hits + stats.misses) || 0,
      memory: process.memoryUsage(),
    };
  },
};

module.exports = cacheWrapper;