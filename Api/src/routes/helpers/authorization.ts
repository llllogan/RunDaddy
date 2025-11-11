import type { Request, Response, NextFunction } from 'express';
import { UserRole } from '../../types/enums.js';

const COMPANY_MANAGER_ROLE_SET = new Set<UserRole>([UserRole.ADMIN, UserRole.OWNER]);

export const COMPANY_MANAGER_ROLES: ReadonlySet<UserRole> = COMPANY_MANAGER_ROLE_SET;

export const isCompanyManager = (role: UserRole): boolean => COMPANY_MANAGER_ROLE_SET.has(role);

export const authorize = (allowedRoles: UserRole[]) => {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.auth) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // For now, we'll check the user's default role
    // In a more complex system, you might want to check company-specific roles
    if (!allowedRoles.includes(req.auth.role)) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }

    next();
  };
};

