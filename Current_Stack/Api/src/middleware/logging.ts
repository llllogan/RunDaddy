import type { Request, Response, NextFunction } from 'express';

export interface LogConfig {
  level: 'minimal' | 'basic' | 'detailed' | 'full';
  maxResponseLength?: number;
  includeFields?: string[];
}

export interface RequestWithLogConfig extends Request {
  logConfig?: LogConfig;
}

const defaultConfig: LogConfig = {
  level: 'basic',
  maxResponseLength: 50,
};

function getLogMessage(
  req: RequestWithLogConfig,
  res: Response,
  responseBody: any,
  config: LogConfig
): string {
  const { method, originalUrl } = req;
  const { statusCode } = res;

  switch (config.level) {
    case 'minimal':
      return `${method} ${originalUrl} - ${statusCode}`;
    
    case 'basic': {
      let responseStr = '';
      if (typeof responseBody === 'string') {
        responseStr = responseBody;
      } else if (Buffer.isBuffer(responseBody)) {
        responseStr = responseBody.toString('utf8');
      } else if (responseBody !== undefined) {
        try {
          responseStr = JSON.stringify(responseBody);
        } catch {
          responseStr = '[unserializable response]';
        }
      }

      const maxLength = config.maxResponseLength || 50;
      const truncatedResponse = responseStr.length > maxLength 
        ? `${responseStr.substring(0, maxLength)}...` 
        : responseStr;
      
      return `${method} ${originalUrl} - ${statusCode} - ${truncatedResponse}`;
    }
    
    case 'detailed': {
      const userAgent = req.get('User-Agent') || 'unknown';
      const ip = req.ip || req.socket.remoteAddress || 'unknown';
      
      let responseStr = '';
      if (typeof responseBody === 'string') {
        responseStr = responseBody;
      } else if (Buffer.isBuffer(responseBody)) {
        responseStr = responseBody.toString('utf8');
      } else if (responseBody !== undefined) {
        try {
          responseStr = JSON.stringify(responseBody);
        } catch {
          responseStr = '[unserializable response]';
        }
      }

      const maxLength = config.maxResponseLength || 200;
      const truncatedResponse = responseStr.length > maxLength 
        ? `${responseStr.substring(0, maxLength)}...` 
        : responseStr;
      
      return `${method} ${originalUrl} - ${statusCode} - ${ip} - ${userAgent} - ${truncatedResponse}`;
    }
    
    case 'full': {
      const headers = JSON.stringify(req.headers);
      const query = JSON.stringify(req.query);
      const body = JSON.stringify(req.body);
      
      let responseStr = '';
      if (typeof responseBody === 'string') {
        responseStr = responseBody;
      } else if (Buffer.isBuffer(responseBody)) {
        responseStr = responseBody.toString('utf8');
      } else if (responseBody !== undefined) {
        try {
          responseStr = JSON.stringify(responseBody);
        } catch {
          responseStr = '[unserializable response]';
        }
      }

      const maxLength = config.maxResponseLength || 10000;
      const truncatedResponse = responseStr.length > maxLength 
        ? `${responseStr.substring(0, maxLength)}...` 
        : responseStr;
      
      return `${method} ${originalUrl} - ${statusCode} - Headers: ${headers} - Query: ${query} - Body: ${body} - Response: ${truncatedResponse}`;
    }
    
    default:
      return `${method} ${originalUrl} - ${statusCode}`;
  }
}

export const loggingMiddleware = (defaultConfigOverride?: Partial<LogConfig>) => {
  const config = { ...defaultConfig, ...defaultConfigOverride };

  return (req: RequestWithLogConfig, res: Response, next: NextFunction) => {
    let responseBody: any;

    const originalJson = res.json;
    res.json = function (body) {
      responseBody = body;
      return originalJson.call(this, body);
    };

    const originalSend = res.send;
    res.send = function (body) {
      responseBody = body;
      return originalSend.call(this, body);
    };

    res.on('finish', () => {
      const finalConfig = req.logConfig ? { ...config, ...req.logConfig } : config;
      const logMessage = getLogMessage(req, res, responseBody, finalConfig);
      console.log(logMessage);
    });

    next();
  };
};

export const setLogConfig = (config: LogConfig) => {
  return (req: RequestWithLogConfig, _res: Response, next: NextFunction) => {
    req.logConfig = config;
    next();
  };
};