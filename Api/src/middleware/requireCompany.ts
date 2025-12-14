import type { NextFunction, Request, Response } from 'express';
import { prisma } from '../lib/prisma.js';

export const requireCompanyContext =
  ({ allowLighthouseWithoutMembership = true }: { allowLighthouseWithoutMembership?: boolean } = {}) =>
  async (req: Request, res: Response, next: NextFunction) => {
    if (!req.auth) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { companyId, userId, lighthouse } = req.auth;

    if (!companyId) {
      return res.status(400).json({ error: 'Company context required' });
    }

    if (!lighthouse || !allowLighthouseWithoutMembership) {
      const membership = await prisma.membership.findUnique({
        where: {
          userId_companyId: {
            userId,
            companyId,
          },
        },
        select: { role: true },
      });

      if (!membership) {
        return res.status(403).json({ error: 'Company membership required' });
      }

      // Keep req.auth role in sync with database membership.
      req.auth.role = membership.role;
    }

    return next();
  };
