import type { NextFunction, Request, Response } from 'express';
import { verifyAccessToken } from '../lib/tokens.js';
import { prisma } from '../lib/prisma.js';

export const authenticate = async (req: Request, res: Response, next: NextFunction) => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing authorization token' });
  }

  const token = authHeader.slice(7).trim();

  try {
    const payload = verifyAccessToken(token);
    if (!payload.sub || !payload.companyId || !payload.context) {
      return res.status(401).json({ error: 'Invalid token payload' });
    }

    const membership = await prisma.membership.findUnique({
      where: {
        userId_companyId: {
          userId: payload.sub,
          companyId: payload.companyId,
        },
      },
      select: {
        role: true,
        companyId: true,
        user: {
          select: {
            id: true,
            email: true,
          },
        },
      },
    });

    if (!membership) {
      return res.status(401).json({ error: 'Membership not found' });
    }

    req.auth = {
      userId: membership.user.id,
      email: membership.user.email,
      role: membership.role,
      companyId: membership.companyId,
      context: payload.context,
    };
    return next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid or expired token', detail: (error as Error).message });
  }
};
