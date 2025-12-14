import type { NextFunction, Request, Response } from 'express';
import { verifyAccessToken } from '../lib/tokens.js';
import { prisma } from '../lib/prisma.js';
import { AccountRole, UserRole } from '../types/enums.js';

const FALLBACK_ROLE = UserRole.PICKER;

export const authenticate = async (req: Request, res: Response, next: NextFunction) => {
  let token: string | undefined;

  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    token = authHeader.slice(7).trim();
  } else if (req.cookies.accessToken) {
    token = req.cookies.accessToken;
  }

  if (!token) {
    return res.status(401).json({ error: 'Missing authorization token' });
  }

  try {
    const payload = verifyAccessToken(token);
    if (!payload.sub || !payload.context) {
      return res.status(401).json({ error: 'Invalid token payload' });
    }
    if (payload.companyId === null || typeof payload.companyId === 'undefined') {
      return res.status(401).json({ error: 'Company context missing from token' });
    }
    const isLighthouse = Boolean((payload as Record<string, unknown>).lighthouse);
    const payloadRole = (payload as Record<string, unknown>).role as UserRole | undefined;

    if (isLighthouse) {
      const user = await prisma.user.findUnique({
        where: { id: payload.sub },
        select: { id: true, email: true, role: true },
      });

      if (!user) {
        return res.status(401).json({ error: 'User not found' });
      }

      req.auth = {
        userId: user.id,
        email: user.email,
        role: payloadRole ?? UserRole.OWNER,
        companyId: payload.companyId,
        context: payload.context,
        lighthouse: true,
        accountRole: (user.role as AccountRole | null | undefined) ?? null,
      };
      return next();
    }

    // Handle users with company memberships
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
            role: true,
          },
        },
      },
    });

    if (!membership) {
      const fallbackUser = await prisma.user.findUnique({
        where: { id: payload.sub },
        select: {
          id: true,
          email: true,
          role: true,
        },
      });

      if (!fallbackUser) {
        return res.status(401).json({ error: 'User not found' });
      }

      req.auth = {
        userId: fallbackUser.id,
        email: fallbackUser.email,
        role: payloadRole ?? FALLBACK_ROLE,
        companyId: null,
        context: payload.context,
        lighthouse: false,
        accountRole: (fallbackUser.role as AccountRole | null | undefined) ?? null,
      };
      return next();
    }

    req.auth = {
      userId: membership.user.id,
      email: membership.user.email,
      role: membership.role,
      companyId: membership.companyId,
      context: payload.context,
      lighthouse: false,
      accountRole: (membership.user.role as AccountRole | null | undefined) ?? null,
    };
    return next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid or expired token', detail: (error as Error).message });
  }
};
