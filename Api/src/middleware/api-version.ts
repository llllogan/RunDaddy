import type { RequestHandler } from 'express';
import { apiVersion } from '../config/version.js';

export const apiVersionMiddleware = (): RequestHandler => (_req, res, next) => {
  res.setHeader('X-App-Version', apiVersion);
  next();
};
