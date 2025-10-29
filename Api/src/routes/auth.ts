import { Router } from 'express';
import type { Response } from 'express';
import { z } from 'zod';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { hashPassword, verifyPassword } from '../lib/password.js';
import { createTokenPair, verifyRefreshToken } from '../lib/tokens.js';
import { authenticate } from '../middleware/authenticate.js';

const router = Router();

const registerSchema = z.object({
  companyName: z.string().min(2),
  userFirstName: z.string().min(1),
  userLastName: z.string().min(1),
  userEmail: z.string().email(),
  userPassword: z.string().min(8),
  userPhone: z.string().min(7).optional(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
  companyId: z.string().cuid().optional(),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(10),
});

type SessionCompany = { id: string; name: string };
type SessionUser = {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: UserRole;
  phone?: string | null;
};

type SessionTokens = {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: Date;
  refreshTokenExpiresAt: Date;
};

const respondWithSession = (
  res: Response,
  data: {
    company: SessionCompany;
    user: SessionUser;
    tokens: SessionTokens;
  },
  status = 200,
) => {
  return res.status(status).json({
    company: data.company,
    user: {
      id: data.user.id,
      email: data.user.email,
      firstName: data.user.firstName,
      lastName: data.user.lastName,
      role: data.user.role,
      phone: data.user.phone ?? null,
    },
    tokens: {
      accessToken: data.tokens.accessToken,
      refreshToken: data.tokens.refreshToken,
      accessTokenExpiresAt: data.tokens.accessTokenExpiresAt.toISOString(),
      refreshTokenExpiresAt: data.tokens.refreshTokenExpiresAt.toISOString(),
    },
  });
};

const buildSessionPayload = (
  user: SessionUser,
  company: SessionCompany,
  tokens: SessionTokens,
) => ({
  company,
  user,
  tokens,
});

router.post('/register', async (req, res) => {
  const parsed = registerSchema.safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { companyName, userFirstName, userLastName, userEmail, userPassword, userPhone } = parsed.data;

  const existingUser = await prisma.user.findUnique({ where: { email: userEmail } });
  if (existingUser) {
    return res.status(409).json({ error: 'Email already registered' });
  }

  const passwordHash = await hashPassword(userPassword);

  const company = await prisma.company.create({ data: { name: companyName } });
  const user = await prisma.user.create({
    data: {
      email: userEmail,
      password: passwordHash,
      firstName: userFirstName,
      lastName: userLastName,
      phone: userPhone ?? null,
      role: UserRole.OWNER,
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: UserRole.OWNER,
    },
  });

  const tokens = createTokenPair({
    userId: user.id,
    companyId: company.id,
    email: user.email,
    role: membership.role,
  });

  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenId: tokens.refreshTokenId,
      expiresAt: tokens.refreshTokenExpiresAt,
    },
  });

  return respondWithSession(
    res,
    buildSessionPayload(
      {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: membership.role,
        phone: user.phone,
      },
      { id: company.id, name: company.name },
      tokens,
    ),
    201,
  );
});

router.post('/login', async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { email, password, companyId } = parsed.data;

  const user = await prisma.user.findUnique({
    where: { email },
    include: {
      memberships: {
        include: {
          company: true,
        },
      },
    },
  });

  if (!user) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const valid = await verifyPassword(password, user.password);
  if (!valid) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const memberships = (user.memberships ?? []) as Array<{
    companyId: string;
    role: UserRole;
    company: { id: string; name: string };
  }>;

  if (!memberships.length) {
    return res.status(403).json({ error: 'No active company memberships for this account' });
  }

  const firstMembership = memberships[0];
  if (!firstMembership) {
    return res.status(500).json({ error: 'Unable to resolve company membership' });
  }

  let membership = firstMembership;
  if (companyId) {
    const selected = memberships.find((member) => member.companyId === companyId);
    if (!selected) {
      return res.status(404).json({ error: 'Membership not found for provided company' });
    }
    membership = selected;
  } else if (memberships.length > 1) {
    return res.status(412).json({
      error: 'Multiple company memberships. Provide companyId to select one.',
      memberships: memberships.map((member) => ({ companyId: member.companyId, companyName: member.company.name })),
    });
  }

  const tokens = createTokenPair({
    userId: user.id,
    companyId: membership.companyId,
    email: user.email,
    role: membership.role,
  });

  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenId: tokens.refreshTokenId,
      expiresAt: tokens.refreshTokenExpiresAt,
    },
  });

  return respondWithSession(
    res,
    buildSessionPayload(
      {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: membership.role,
        phone: user.phone,
      },
      { id: membership.company.id, name: membership.company.name },
      tokens,
    ),
  );
});

router.post('/refresh', async (req, res) => {
  const parsed = refreshSchema.safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { refreshToken } = parsed.data;

  try {
    const payload = verifyRefreshToken(refreshToken);

    const stored = await prisma.refreshToken.findUnique({
      where: { tokenId: payload.tokenId },
    });

    if (!stored || stored.revoked || stored.expiresAt.getTime() < Date.now()) {
      return res.status(401).json({ error: 'Refresh token expired or revoked' });
    }

    if (stored.userId !== payload.sub) {
      return res.status(401).json({ error: 'Refresh token invalid for this account' });
    }

    const user = await prisma.user.findUnique({
      where: { id: payload.sub },
      include: {
        memberships: {
          where: { companyId: payload.companyId },
          include: { company: true },
        },
      },
    });

    if (!user || !user.memberships.length) {
      return res.status(401).json({ error: 'Account not available' });
    }

    const membership = user.memberships[0];

    const tokens = createTokenPair({
      userId: user.id,
      companyId: membership.companyId,
      email: user.email,
      role: membership.role,
    });

    await prisma.$transaction([
      prisma.refreshToken.update({
        where: { tokenId: stored.tokenId },
        data: { revoked: true },
      }),
      prisma.refreshToken.create({
        data: {
          userId: user.id,
          tokenId: tokens.refreshTokenId,
          expiresAt: tokens.refreshTokenExpiresAt,
        },
      }),
    ]);

    return respondWithSession(
      res,
      buildSessionPayload(
        {
          id: user.id,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          role: membership.role,
          phone: user.phone,
        },
        { id: membership.company.id, name: membership.company.name },
        tokens,
      ),
    );
  } catch (error) {
    return res.status(401).json({ error: 'Unable to refresh token', detail: (error as Error).message });
  }
});

router.get('/me', authenticate, async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const membership = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId: req.auth.userId,
        companyId: req.auth.companyId,
      },
    },
    include: {
      user: true,
      company: true,
    },
  });

  if (!membership) {
    return res.status(404).json({ error: 'Membership not found' });
  }

  return res.json({
    company: { id: membership.company.id, name: membership.company.name },
    user: {
      id: membership.user.id,
      email: membership.user.email,
      firstName: membership.user.firstName,
      lastName: membership.user.lastName,
      role: membership.role,
      phone: membership.user.phone,
    },
  });
});

export const authRouter = router;
