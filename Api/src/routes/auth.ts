import { Router } from 'express';
import type { Prisma } from '@prisma/client';
import { AuthContext, UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { hashPassword, verifyPassword } from '../lib/password.js';
import { createTokenPair, verifyRefreshToken, verifyAccessToken } from '../lib/tokens.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { userHasPlatformAdminAccess } from '../lib/platform-admin.js';
import { PLATFORM_ADMIN_COMPANY_ID } from '../config/platform-admin.js';
import { DEFAULT_COMPANY_TIER_ID } from '../config/tiers.js';
import {
  registerSchema,
  signupSchema,
  loginSchema,
  switchCompanySchema,
  getAllowedRolesForContext,
  formatMembershipChoices,
  respondWithSession,
  buildSessionPayload,
  buildAuthCookieOptions,
  type MembershipSummary,
} from './helpers/auth.js';

const router = Router();

// Creates a new user account without a company, returning initial session tokens.
router.post('/signup', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const parsed = signupSchema.safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { userFirstName, userLastName, userEmail, userPassword, userPhone } = parsed.data;

  const existingUser = await prisma.user.findUnique({ where: { email: userEmail } });
  if (existingUser) {
    return res.status(409).json({ error: 'Email already registered' });
  }

  const passwordHash = await hashPassword(userPassword);

  const user = await prisma.user.create({
    data: {
      email: userEmail,
      password: passwordHash,
      firstName: userFirstName,
      lastName: userLastName,
      phone: userPhone ?? null,
      role: UserRole.PICKER,
    },
  });

  const tokens = createTokenPair({
    userId: user.id,
    companyId: null, // No company for standalone accounts
    email: user.email,
    role: user.role,
    context: AuthContext.APP,
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
        role: user.role,
        phone: user.phone,
        platformAdmin: false,
      },
      null, // No company for standalone accounts
      tokens,
      null,
    ),
    201,
  );
});

// Registers a new company and owner account, returning initial session tokens.
router.post('/register', setLogConfig({ level: 'minimal' }), async (req, res) => {
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

  const company = await prisma.company.create({
    data: { name: companyName, tierId: DEFAULT_COMPANY_TIER_ID },
  });
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
        platformAdmin: false,
      },
      { id: company.id, name: company.name },
      tokens,
      null,
    ),
    201,
  );
});

// Authenticates a user and establishes a session for the selected company.
router.post('/login', setLogConfig({ level: 'minimal' }), async (req, res) => {
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

  const platformAdmin = loadedMemberships.some(
    (member) => member.companyId === PLATFORM_ADMIN_COMPANY_ID && member.role === UserRole.GOD,
  );
  const platformAdminCompanyId = platformAdmin ? PLATFORM_ADMIN_COMPANY_ID : null;

  // For APP context, allow users without company memberships
  if (!memberships.length && context !== AuthContext.APP) {
    return res.status(403).json({ error: 'No active company memberships for this account' });
  }

  // Handle users without company memberships for APP context
  if (!memberships.length && context === AuthContext.APP) {
    const tokens = createTokenPair({
      userId: user.id,
      companyId: null,
      email: user.email,
      role: user.role,
      context,
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
          role: user.role,
          phone: user.phone,
          platformAdmin: false,
        },
        null,
        tokens,
        null,
      ),
    );
  }

  const allowedRoles = getAllowedRolesForContext(context);
  const eligibleMemberships = memberships.filter((member) => allowedRoles.has(member.role));

  if (context === AuthContext.WEB && !eligibleMemberships.length) {
    return res.status(403).json({ error: 'Web dashboard requires GOD, ADMIN, or OWNER membership' });
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
        platformAdmin,
      },
      { id: membership.company.id, name: membership.company.name },
      tokens,
      platformAdminCompanyId,
    ),
  );
});

// Issues a new access token pair when provided with a valid refresh token cookie.
router.post('/refresh', setLogConfig({ level: 'minimal' }), async (req, res) => {
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

    const platformAdmin = await userHasPlatformAdminAccess(payload.sub);
    const platformAdminCompanyId = platformAdmin ? PLATFORM_ADMIN_COMPANY_ID : null;

    if (!payload.companyId) {
      const user = await prisma.user.findUnique({
        where: { id: payload.sub },
        select: {
          id: true,
          email: true,
          firstName: true,
          lastName: true,
          phone: true,
          role: true,
        },
      });

      if (!user) {
        return res.status(401).json({ error: 'Account not available' });
      }

      const allowedRoles = getAllowedRolesForContext(payload.context);
      if (!allowedRoles.has(user.role)) {
        return res.status(403).json({ error: 'User role not permitted for this client' });
      }

      const tokens = createTokenPair({
        userId: user.id,
        companyId: null,
        email: user.email,
        role: user.role,
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
            role: user.role,
            phone: user.phone,
            platformAdmin,
          },
          null,
          tokens,
          platformAdminCompanyId,
        ),
      );
    }

    const user = await prisma.user.findUnique({
      where: { id: payload.sub },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        phone: true,
        role: true,
        memberships: {
          where: { companyId: payload.companyId },
          include: { company: true },
        },
      },
    });

    if (!user || !user.memberships?.length) {
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
          platformAdmin,
        },
        { id: membership.company.id, name: membership.company.name },
        tokens,
        platformAdminCompanyId,
      ),
    );
  } catch (error) {
    return res.status(401).json({ error: 'Invalid or expired refresh token', detail: (error as Error).message });
  }
});

// Switches the active company for the authenticated session and rotates tokens.
router.post('/switch-company', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
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

  const platformAdmin = await userHasPlatformAdminAccess(membershipRecord.user.id);
  const platformAdminCompanyId = platformAdmin ? PLATFORM_ADMIN_COMPANY_ID : null;

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
        platformAdmin,
      },
      { id: membership.company.id, name: membership.company.name },
      tokens,
      platformAdminCompanyId,
    ),
  );
});

// Clears authentication cookies to log the user out.
router.post('/logout', setLogConfig({ level: 'minimal' }), (req, res) => {
  const cookieOptions = buildAuthCookieOptions();
  res.clearCookie('accessToken', cookieOptions);
  res.clearCookie('refreshToken', cookieOptions);
  res.status(200).json({ message: 'Logged out' });
});

// Returns the authenticated user's profile and company context.
router.get('/me', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Get all user memberships
  const memberships = await prisma.membership.findMany({
    where: { userId: req.auth.userId },
    include: {
      company: true,
      user: true,
    },
  });

  const companies = memberships.map(membership => ({
    id: membership.company.id,
    name: membership.company.name,
    role: membership.role,
    location: membership.company.location ?? null,
    timeZone: membership.company.timeZone ?? null,
  }));

  const platformAdmin = memberships.some(
    (membership) => membership.companyId === PLATFORM_ADMIN_COMPANY_ID && membership.role === UserRole.GOD,
  );
  const platformAdminCompanyId = platformAdmin ? PLATFORM_ADMIN_COMPANY_ID : null;

  // Handle users without company memberships
  if (memberships.length === 0) {
    const user = await prisma.user.findUnique({
      where: { id: req.auth.userId },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        role: true,
        phone: true,
      },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const standalonePlatformAdmin = platformAdmin || (await userHasPlatformAdminAccess(req.auth.userId));
    const standalonePlatformAdminCompanyId = standalonePlatformAdmin ? PLATFORM_ADMIN_COMPANY_ID : null;

    return res.json({
      companies: [],
      currentCompany: null,
      user: {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role,
        phone: user.phone,
        platformAdmin: standalonePlatformAdmin,
      },
      platformAdminCompanyId: standalonePlatformAdminCompanyId,
    });
  }

  // Handle users with company memberships
  let currentCompany = null;
  const auth = req.auth; // Store to avoid repeated optional chaining
  if (auth && auth.companyId) {
      const currentMembership = memberships.find(m => m.companyId === auth.companyId);
      if (currentMembership) {
        currentCompany = {
          id: currentMembership.company.id,
          name: currentMembership.company.name,
          role: currentMembership.role,
          location: currentMembership.company.location ?? null,
          timeZone: currentMembership.company.timeZone ?? null,
        };
      }
    }

  // Use the first membership's user data (should be consistent across all memberships)
  const user = memberships[0]?.user;
  if (!user) {
    return res.status(500).json({ error: 'Unable to retrieve user data' });
  }

  return res.json({
    companies,
    currentCompany,
    user: {
      id: user.id,
      email: user.email,
      firstName: user.firstName,
      lastName: user.lastName,
      role: currentCompany?.role ?? user.role,
      phone: user.phone,
      platformAdmin,
    },
    platformAdminCompanyId,
  });
});

// Returns user profile for standalone accounts (without company requirement)
router.get('/profile/:userId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const { userId } = req.params;
  
  if (!userId) {
    return res.status(400).json({ error: 'User ID is required' });
  }
  
  let token: string | undefined;
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    token = authHeader.slice(7).trim();
  }

  if (!token) {
    return res.status(401).json({ error: 'Missing authorization token' });
  }

  try {
    const payload = verifyAccessToken(token);
    if (!payload.sub || !payload.context) {
      return res.status(401).json({ error: 'Invalid token payload' });
    }

    // Allow access if token is for the requested user or if user has no company
    if (payload.sub !== userId && payload.companyId !== null) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        phone: true,
        role: true,
      },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    return res.json({
      id: user.id,
      email: user.email,
      firstName: user.firstName,
      lastName: user.lastName,
      role: user.role,
      phone: user.phone,
    });
  } catch (error) {
    return res.status(401).json({ error: 'Invalid or expired token', detail: (error as Error).message });
  }
});

export const authRouter = router;
