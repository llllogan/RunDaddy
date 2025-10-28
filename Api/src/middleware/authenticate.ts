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
    if (!payload.sub || !payload.companyId) {
      return res.status(401).json({ error: 'Invalid token payload' });
    }

    const user = await prisma.user.findUnique({
      where: { id: payload.sub },
      select: {
        id: true,
        email: true,
        role: true,
        companyId: true,
      },
    });

    if (!user) {
      return res.status(401).json({ error: 'Account not found' });
    }

    req.auth = {
      userId: user.id,
      email: user.email,
      role: user.role,
      companyId: user.companyId,
    };
    return next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid or expired token', detail: (error as Error).message });
  }
};
