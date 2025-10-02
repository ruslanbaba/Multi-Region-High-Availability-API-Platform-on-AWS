const AWS = require('aws-sdk');
const config = require('../config');
const logger = require('../utils/logger');
const cache = require('../utils/cache');

// Configure AWS SDK
AWS.config.update({
  region: config.aws.region,
  accessKeyId: config.aws.accessKeyId,
  secretAccessKey: config.aws.secretAccessKey,
});

// Initialize DynamoDB client
const dynamoDB = new AWS.DynamoDB.DocumentClient({
  region: config.aws.region,
  httpOptions: {
    timeout: 5000,
    connectTimeout: 3000,
  },
  maxRetries: 3,
  retryDelayOptions: {
    customBackoff: function(retryCount) {
      return Math.pow(2, retryCount) * 100; // Exponential backoff
    }
  }
});

/**
 * Base Database Class
 * Provides common database operations with caching and error handling
 */
class BaseDatabase {
  constructor(tableName) {
    this.tableName = tableName;
    this.client = dynamoDB;
  }

  /**
   * Create a new item
   */
  async create(item) {
    try {
      const timestamp = new Date().toISOString();
      const itemWithTimestamps = {
        ...item,
        id: item.id || this.generateId(),
        createdAt: timestamp,
        updatedAt: timestamp,
      };

      const params = {
        TableName: this.tableName,
        Item: itemWithTimestamps,
        ConditionExpression: 'attribute_not_exists(id)',
      };

      await this.client.put(params).promise();
      
      // Invalidate cache
      this.invalidateCache(itemWithTimestamps.id);
      
      logger.debug({ 
        table: this.tableName, 
        itemId: itemWithTimestamps.id 
      }, 'Item created successfully');
      
      return itemWithTimestamps;
    } catch (error) {
      logger.error({ 
        error: error.message, 
        table: this.tableName, 
        item 
      }, 'Failed to create item');
      
      if (error.code === 'ConditionalCheckFailedException') {
        throw new Error('Item already exists');
      }
      throw error;
    }
  }

  /**
   * Get item by ID with caching
   */
  async findById(id, useCache = true) {
    try {
      const cacheKey = `${this.tableName}:${id}`;
      
      // Check cache first
      if (useCache) {
        const cached = cache.get(cacheKey);
        if (cached) {
          logger.debug({ table: this.tableName, itemId: id }, 'Item retrieved from cache');
          return cached;
        }
      }

      const params = {
        TableName: this.tableName,
        Key: { id },
      };

      const result = await this.client.get(params).promise();
      
      if (!result.Item) {
        return null;
      }

      // Cache the result
      if (useCache) {
        cache.set(cacheKey, result.Item, config.cache.ttl);
      }
      
      logger.debug({ 
        table: this.tableName, 
        itemId: id 
      }, 'Item retrieved from database');
      
      return result.Item;
    } catch (error) {
      logger.error({ 
        error: error.message, 
        table: this.tableName, 
        itemId: id 
      }, 'Failed to get item by ID');
      throw error;
    }
  }

  /**
   * Update item by ID
   */
  async updateById(id, updates) {
    try {
      // Remove undefined values and add timestamp
      const cleanUpdates = this.cleanUpdates({
        ...updates,
        updatedAt: new Date().toISOString(),
      });

      if (Object.keys(cleanUpdates).length === 1) {
        // Only updatedAt field, nothing to update
        return await this.findById(id, false);
      }

      // Build update expression
      const updateExpression = [];
      const expressionAttributeNames = {};
      const expressionAttributeValues = {};

      Object.keys(cleanUpdates).forEach((key, index) => {
        const attrName = `#attr${index}`;
        const attrValue = `:val${index}`;
        
        updateExpression.push(`${attrName} = ${attrValue}`);
        expressionAttributeNames[attrName] = key;
        expressionAttributeValues[attrValue] = cleanUpdates[key];
      });

      const params = {
        TableName: this.tableName,
        Key: { id },
        UpdateExpression: `SET ${updateExpression.join(', ')}`,
        ExpressionAttributeNames: expressionAttributeNames,
        ExpressionAttributeValues: expressionAttributeValues,
        ConditionExpression: 'attribute_exists(id)',
        ReturnValues: 'ALL_NEW',
      };

      const result = await this.client.update(params).promise();
      
      // Invalidate cache
      this.invalidateCache(id);
      
      logger.debug({ 
        table: this.tableName, 
        itemId: id, 
        updates: cleanUpdates 
      }, 'Item updated successfully');
      
      return result.Attributes;
    } catch (error) {
      logger.error({ 
        error: error.message, 
        table: this.tableName, 
        itemId: id, 
        updates 
      }, 'Failed to update item');
      
      if (error.code === 'ConditionalCheckFailedException') {
        throw new Error('Item not found');
      }
      throw error;
    }
  }

  /**
   * Delete item by ID
   */
  async deleteById(id) {
    try {
      const params = {
        TableName: this.tableName,
        Key: { id },
        ConditionExpression: 'attribute_exists(id)',
        ReturnValues: 'ALL_OLD',
      };

      const result = await this.client.delete(params).promise();
      
      // Invalidate cache
      this.invalidateCache(id);
      
      logger.debug({ 
        table: this.tableName, 
        itemId: id 
      }, 'Item deleted successfully');
      
      return result.Attributes;
    } catch (error) {
      logger.error({ 
        error: error.message, 
        table: this.tableName, 
        itemId: id 
      }, 'Failed to delete item');
      
      if (error.code === 'ConditionalCheckFailedException') {
        throw new Error('Item not found');
      }
      throw error;
    }
  }

  /**
   * Find items with pagination
   */
  async find(options = {}) {
    try {
      const {
        limit = 10,
        lastEvaluatedKey = null,
        indexName = null,
        filterExpression = null,
        expressionAttributeNames = {},
        expressionAttributeValues = {},
        scanIndexForward = true,
      } = options;

      const params = {
        TableName: this.tableName,
        Limit: limit,
        ScanIndexForward: scanIndexForward,
      };

      if (lastEvaluatedKey) {
        params.ExclusiveStartKey = lastEvaluatedKey;
      }

      if (indexName) {
        params.IndexName = indexName;
      }

      if (filterExpression) {
        params.FilterExpression = filterExpression;
        params.ExpressionAttributeNames = expressionAttributeNames;
        params.ExpressionAttributeValues = expressionAttributeValues;
      }

      const result = await this.client.scan(params).promise();
      
      logger.debug({ 
        table: this.tableName, 
        count: result.Items.length,
        hasMore: !!result.LastEvaluatedKey 
      }, 'Items retrieved successfully');
      
      return {
        items: result.Items,
        lastEvaluatedKey: result.LastEvaluatedKey,
        count: result.Count,
        scannedCount: result.ScannedCount,
      };
    } catch (error) {
      logger.error({ 
        error: error.message, 
        table: this.tableName, 
        options 
      }, 'Failed to find items');
      throw error;
    }
  }

  /**
   * Query items by index
   */
  async query(keyConditionExpression, options = {}) {
    try {
      const {
        limit = 10,
        lastEvaluatedKey = null,
        indexName = null,
        filterExpression = null,
        expressionAttributeNames = {},
        expressionAttributeValues = {},
        scanIndexForward = true,
      } = options;

      const params = {
        TableName: this.tableName,
        KeyConditionExpression: keyConditionExpression,
        ExpressionAttributeNames: expressionAttributeNames,
        ExpressionAttributeValues: expressionAttributeValues,
        Limit: limit,
        ScanIndexForward: scanIndexForward,
      };

      if (lastEvaluatedKey) {
        params.ExclusiveStartKey = lastEvaluatedKey;
      }

      if (indexName) {
        params.IndexName = indexName;
      }

      if (filterExpression) {
        params.FilterExpression = filterExpression;
      }

      const result = await this.client.query(params).promise();
      
      logger.debug({ 
        table: this.tableName, 
        count: result.Items.length,
        hasMore: !!result.LastEvaluatedKey 
      }, 'Items queried successfully');
      
      return {
        items: result.Items,
        lastEvaluatedKey: result.LastEvaluatedKey,
        count: result.Count,
        scannedCount: result.ScannedCount,
      };
    } catch (error) {
      logger.error({ 
        error: error.message, 
        table: this.tableName, 
        keyConditionExpression,
        options 
      }, 'Failed to query items');
      throw error;
    }
  }

  /**
   * Batch write operations
   */
  async batchWrite(requests) {
    try {
      const params = {
        RequestItems: {
          [this.tableName]: requests,
        },
      };

      const result = await this.client.batchWrite(params).promise();
      
      // Handle unprocessed items
      if (result.UnprocessedItems && Object.keys(result.UnprocessedItems).length > 0) {
        logger.warn({ 
          table: this.tableName, 
          unprocessedCount: result.UnprocessedItems[this.tableName]?.length || 0 
        }, 'Some items were not processed in batch write');
      }

      logger.debug({ 
        table: this.tableName, 
        requestCount: requests.length 
      }, 'Batch write completed');
      
      return result;
    } catch (error) {
      logger.error({ 
        error: error.message, 
        table: this.tableName, 
        requestCount: requests.length 
      }, 'Failed to perform batch write');
      throw error;
    }
  }

  /**
   * Health check for database connection
   */
  async healthCheck() {
    try {
      const params = {
        TableName: this.tableName,
        Limit: 1,
      };

      await this.client.scan(params).promise();
      return { status: 'healthy', table: this.tableName };
    } catch (error) {
      logger.error({ 
        error: error.message, 
        table: this.tableName 
      }, 'Database health check failed');
      return { status: 'unhealthy', table: this.tableName, error: error.message };
    }
  }

  /**
   * Utility methods
   */
  generateId() {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  cleanUpdates(updates) {
    const cleaned = {};
    for (const [key, value] of Object.entries(updates)) {
      if (value !== undefined && value !== null) {
        cleaned[key] = value;
      }
    }
    return cleaned;
  }

  invalidateCache(id) {
    const cacheKey = `${this.tableName}:${id}`;
    cache.del(cacheKey);
  }

  getCacheInfo() {
    return cache.getInfo();
  }
}

module.exports = BaseDatabase;