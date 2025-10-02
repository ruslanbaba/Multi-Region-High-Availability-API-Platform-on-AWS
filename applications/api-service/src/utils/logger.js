const pino = require('pino');
const config = require('../config');

const logger = pino({
  level: config.logging.level,
  formatters: {
    level: (label) => {
      return { level: label.toUpperCase() };
    },
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  base: {
    pid: process.pid,
    hostname: process.env.HOSTNAME || 'unknown',
    service: config.app.name,
    version: config.app.version,
    environment: config.environment,
    region: config.aws.region,
  },
  ...(config.logging.pretty && {
    transport: {
      target: 'pino-pretty',
      options: {
        colorize: true,
        translateTime: 'SYS:yyyy-mm-dd HH:MM:ss.l',
        ignore: 'pid,hostname',
      },
    },
  }),
});

module.exports = logger;