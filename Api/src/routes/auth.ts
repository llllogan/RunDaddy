import { Router } from 'express';
import type { Response } from 'express';
import type { Prisma } from '@prisma/client';
import { z } from 'zod';
import { AuthContext, UserRole } from '../types/enums.js';
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
  context: z.nativeEnum(AuthContext).default(AuthContext.WEB),
  setAsDefault: z.boolean().optional(),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(10),
});

const switchCompanySchema = z.object({
  companyId: z.string().cuid(),
  context: z.nativeEnum(AuthContext).optional(),
  persist: z.boolean().optional(),
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
  context: AuthContext;
};

type MembershipSummary = {
  id: string;
  companyId: string;
  role: UserRole;
  company: { id: string; name: string };
};

const WEB_ALLOWED_ROLES = new Set<UserRole>([UserRole.ADMIN, UserRole.OWNER]);
const ALL_ALLOWED_ROLES = new Set<UserRole>(Object.values(UserRole));

const getAllowedRolesForContext = (context: AuthContext): Set<UserRole> => {
  return context === AuthContext.WEB ? WEB_ALLOWED_ROLES : ALL_ALLOWED_ROLES;
};

const formatMembershipChoices = (memberships: MembershipSummary[]) =>
  memberships.map((member) => ({
    companyId: member.companyId,
    companyName: member.company.name,
    role: member.role,
  }));

const respondWithSession = (
  res: Response,
  data: {
    company: SessionCompany;
    user: SessionUser;
    tokens: SessionTokens;
  },
  status = 200,
) => {
  const isProduction = process.env.NODE_ENV === 'production';
  const cookieOptions = {
    httpOnly: true,
    secure: isProduction,
    sameSite: 'strict' as const,
    path: '/',
  };

  res.cookie('accessToken', data.tokens.accessToken, {
    ...cookieOptions,
    expires: data.tokens.accessTokenExpiresAt,
  });
  res.cookie('refreshToken', data.tokens.refreshToken, {
    ...cookieOptions,
    expires: data.tokens.refreshTokenExpiresAt,
  });

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
  await prisma.user.update({
    where: { id: user.id },
    data: { defaultMembershipId: membership.id },
  });

  const tokens = createTokenPair({
    userId: user.id,
    companyId: company.id,
    email: user.email,
    role: membership.role,
    context: AuthContext.WEB,
  });

  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenId: tokens.refreshTokenId,
      expiresAt: tokens.refreshTokenExpiresAt,
      context: tokens.context,
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

  const { email, password, companyId, context, setAsDefault } = parsed.data;

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

  type LoadedMembership = {
    id: string;
    companyId: string;
    role: UserRole;
    company: { id: string; name: string };
  };

  const loadedMemberships = (user.memberships ?? []) as LoadedMembership[];

  const memberships: MembershipSummary[] = loadedMemberships.map((membership) => ({
    id: membership.id,
    companyId: membership.companyId,
    role: membership.role as UserRole,
    company: { id: membership.company.id, name: membership.company.name },
  }));

  if (!memberships.length) {
    return res.status(403).json({ error: 'No active company memberships for this account' });
  }

  const allowedRoles = getAllowedRolesForContext(context);
  const eligibleMemberships = memberships.filter((member) => allowedRoles.has(member.role));

  if (context === AuthContext.WEB && !eligibleMemberships.length) {
    return res.status(403).json({ error: 'Web dashboard requires ADMIN or OWNER membership' });
  }

  let membership: MembershipSummary | undefined;
  const defaultMembershipId = user.defaultMembershipId ?? null;
  let persistDefault = context === AuthContext.WEB && Boolean(setAsDefault);

  if (companyId) {
    const selected = memberships.find((member) => member.companyId === companyId);
    if (!selected) {
      return res.status(404).json({ error: 'Membership not found for provided company' });
    }
    if (!allowedRoles.has(selected.role)) {
      return res.status(403).json({ error: 'Membership role not permitted for this client' });
    }
    membership = selected;
  } else if (context === AuthContext.WEB) {
    if (defaultMembershipId) {
      membership = eligibleMemberships.find((member) => member.id === defaultMembershipId);
    }

    if (!membership && eligibleMemberships.length === 1) {
      membership = eligibleMemberships[0];
      persistDefault = true;
    }

    if (!membership) {
      return res.status(412).json({
        error: 'Multiple company memberships. Provide companyId to select one or set a default.',
        memberships: formatMembershipChoices(eligibleMemberships),
      });
    }
  } else {
    if (defaultMembershipId) {
      membership = memberships.find((member) => member.id === defaultMembershipId);
    }

    if (!membership) {
      membership = memberships[0];
    }
  }

  if (!membership) {
    return res.status(500).json({ error: 'Unable to resolve company membership' });
  }

  const tokens = createTokenPair({
    userId: user.id,
    companyId: membership.companyId,
    email: user.email,
    role: membership.role,
    context,
  });

  const writes: Prisma.PrismaPromise<unknown>[] = [
    prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenId: tokens.refreshTokenId,
        expiresAt: tokens.refreshTokenExpiresAt,
        context: tokens.context,
      },
    }),
  ];

  if (
    context === AuthContext.WEB &&
    persistDefault &&
    membership.id !== user.defaultMembershipId
  ) {
    writes.push(
      prisma.user.update({
        where: { id: user.id },
        data: { defaultMembershipId: membership.id },
      }),
    );
  }

  if (writes.length > 1) {
    await prisma.$transaction(writes);
  } else {
    await writes[0];
  }

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
  const refreshToken = req.cookies.refreshToken;
  if (!refreshToken || typeof refreshToken !== 'string') {
    return res.status(401).json({ error: 'Refresh token required' });
  }

  try {
    const payload = verifyRefreshToken(refreshToken);

    const stored = await prisma.refreshToken.findUnique({
      where: { tokenId: payload.tokenId },
    });

    if (!stored || stored.revoked || stored.expiresAt.getTime() < Date.now()) {
      return res.status(401).json({ error: 'Refresh token expired or revoked' });
    }

    if (stored.userId !== payload.sub || stored.context !== payload.context) {
      return res.status(401).json({ error: 'Refresh token invalid for this account' });
    }

    const user = await prisma.user.findUnique({
      where: { id: payload.sub },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        phone: true,
        memberships: {
          where: { companyId: payload.companyId },
          include: { company: true },
        },
      },
    });

    if (!user || !user.memberships.length) {
      return res.status(401).json({ error: 'Account not available' });
    }

    const membershipRecord = user.memberships[0]!;
    const membership: MembershipSummary = {
      id: membershipRecord.id,
      companyId: membershipRecord.companyId,
      role: membershipRecord.role,
      company: { id: membershipRecord.company.id, name: membershipRecord.company.name },
    };

    const allowedRoles = getAllowedRolesForContext(payload.context);
    if (!allowedRoles.has(membership.role)) {
      return res.status(403).json({ error: 'Membership role not permitted for this client' });
    }

    const tokens = createTokenPair({
      userId: user.id,
      companyId: membership.companyId,
      email: user.email,
      role: membership.role,
      context: payload.context,
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
          context: tokens.context,
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
    return res.status(401).json({ error: 'Invalid or expired refresh token', detail: (error as Error).message });
  }
});

router.post('/switch-company', authenticate, async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const parsed = switchCompanySchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { companyId, context, persist } = parsed.data;
  const targetContext = context ?? req.auth.context ?? AuthContext.WEB;
  const allowedRoles = getAllowedRolesForContext(targetContext);

    const membershipRecord = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId: req.auth.userId,
        companyId,
      },
    },
    include: {
      company: true,
      user: {
        select: {
          id: true,
          email: true,
          firstName: true,
          lastName: true,
          phone: true,
          defaultMembershipId: true,
        },
      },
    },
  });

  if (!membershipRecord) {
    return res.status(404).json({ error: 'Membership not found for provided company' });
  }

  if (!allowedRoles.has(membershipRecord.role)) {
    return res.status(403).json({ error: 'Membership role not permitted for this client' });
  }

  const membership: MembershipSummary = {
    id: membershipRecord.id,
    companyId: membershipRecord.companyId,
    role: membershipRecord.role,
    company: { id: membershipRecord.company.id, name: membershipRecord.company.name },
  };

  const tokens = createTokenPair({
    userId: membershipRecord.user.id,
    companyId: membership.companyId,
    email: membershipRecord.user.email,
    role: membership.role,
    context: targetContext,
  });

  const shouldPersist =
    targetContext === AuthContext.WEB &&
    (persist ?? true) &&
    membershipRecord.user.defaultMembershipId !== membership.id;

  const writes: Prisma.PrismaPromise<unknown>[] = [
    prisma.refreshToken.create({
      data: {
        userId: membershipRecord.user.id,
        tokenId: tokens.refreshTokenId,
        expiresAt: tokens.refreshTokenExpiresAt,
        context: tokens.context,
      },
    }),
  ];

  if (shouldPersist) {
    writes.push(
      prisma.user.update({
        where: { id: membershipRecord.user.id },
        data: { defaultMembershipId: membership.id },
      }),
    );
  }

  if (writes.length > 1) {
    await prisma.$transaction(writes);
  } else {
    await writes[0];
  }

  return respondWithSession(
    res,
    buildSessionPayload(
      {
        id: membershipRecord.user.id,
        email: membershipRecord.user.email,
        firstName: membershipRecord.user.firstName,
        lastName: membershipRecord.user.lastName,
        role: membership.role,
        phone: membershipRecord.user.phone,
      },
      { id: membership.company.id, name: membership.company.name },
      tokens,
    ),
  );
});

router.post('/logout', (req, res) => {
  res.clearCookie('accessToken');
  res.clearCookie('refreshToken');
  res.status(200).json({ message: 'Logged out' });
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
