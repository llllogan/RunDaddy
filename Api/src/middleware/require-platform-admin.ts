import type { NextFunction, Request, Response } from 'express';
import { PLATFORM_ADMIN_COMPANY_ID } from '../config/platform-admin.js';
import { UserRole } from '../types/enums.js';

export const requirePlatformAdmin = (req: Request, res: Response, next: NextFunction) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (req.auth.companyId !== PLATFORM_ADMIN_COMPANY_ID || req.auth.role !== UserRole.ADMIN) {
    return res.status(403).json({ error: 'Platform admin access required' });
  }

  return next();
};
