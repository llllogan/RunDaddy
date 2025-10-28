import { Router } from 'express';
import type { Response } from 'express';
import { z } from 'zod';
import { AdminRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { hashPassword, verifyPassword } from '../lib/password.js';
import { buildCompanySlug } from '../lib/slug.js';
import { createTokenPair, verifyRefreshToken } from '../lib/tokens.js';
import { authenticate } from '../middleware/authenticate.js';

const router = Router();

const registerSchema = z.object({
  companyName: z.string().min(2),
  companyDescription: z.string().min(1).optional(),
  adminFirstName: z.string().min(1),
  adminLastName: z.string().min(1),
  adminEmail: z.string().email(),
  adminPassword: z.string().min(8),
  adminPhone: z.string().min(7).optional(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(10),
});

const makeCompanySlug = async (name: string): Promise<string> => {
  const base = buildCompanySlug(name);
  let candidate = base;
  let counter = 1;

  // Ensure uniqueness by appending a counter if needed.
  // This loop is safe because of the unique constraint and short-circuit on the first available slug.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const existing = await prisma.company.findUnique({ where: { slug: candidate } });
    if (!existing) {
      return candidate;
    }
    counter += 1;
    candidate = `${base}-${counter}`;
  }
};

const respondWithSession = (
  res: Response,
  data: {
    company: { id: string; name: string; slug: string };
    admin: { id: string; email: string; firstName: string; lastName: string; role: AdminRole; phone?: string | null };
    accessToken: string;
    refreshToken: string;
    accessTokenExpiresAt: Date;
    refreshTokenExpiresAt: Date;
  },
  status = 200,
) => {
  return res.status(status).json({
    company: data.company,
    admin: data.admin,
    tokens: {
      accessToken: data.accessToken,
      refreshToken: data.refreshToken,
      accessTokenExpiresAt: data.accessTokenExpiresAt.toISOString(),
      refreshTokenExpiresAt: data.refreshTokenExpiresAt.toISOString(),
    },
  });
};

router.post('/register', async (req, res) => {
  const result = registerSchema.safeParse(req.body);

  if (!result.success) {
    return res.status(400).json({ error: 'Invalid payload', details: result.error.flatten() });
  }

  const {
    companyName,
    companyDescription,
    adminFirstName,
    adminLastName,
    adminEmail,
    adminPassword,
    adminPhone,
  } = result.data;

  const existingAdmin = await prisma.admin.findUnique({ where: { email: adminEmail } });
  if (existingAdmin) {
    return res.status(409).json({ error: 'Email already registered' });
  }

  const slug = await makeCompanySlug(companyName);
  const passwordHash = await hashPassword(adminPassword);

  const company = await prisma.company.create({
    data: {
      name: companyName,
      slug,
      description: companyDescription ?? null,
      admins: {
        create: {
          email: adminEmail,
          password: passwordHash,
          firstName: adminFirstName,
          lastName: adminLastName,
          role: AdminRole.ADMIN,
          phone: adminPhone ?? null,
        },
      },
    },
    include: {
      admins: true,
    },
  });

  const admin = company.admins[0];

  if (!admin) {
    return res.status(500).json({ error: 'Failed to create admin account' });
  }

  const tokens = createTokenPair({
    adminId: admin.id,
    companyId: company.id,
    email: admin.email,
    role: admin.role,
  });

  await prisma.refreshToken.create({
    data: {
      adminId: admin.id,
      tokenId: tokens.refreshTokenId,
      expiresAt: tokens.refreshTokenExpiresAt,
    },
  });

  return respondWithSession(
    res,
    {
      company: { id: company.id, name: company.name, slug: company.slug },
      admin: {
        id: admin.id,
        email: admin.email,
        firstName: admin.firstName,
        lastName: admin.lastName,
        role: admin.role,
        phone: admin.phone,
      },
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessTokenExpiresAt: tokens.accessTokenExpiresAt,
      refreshTokenExpiresAt: tokens.refreshTokenExpiresAt,
    },
    201,
  );
});

router.post('/login', async (req, res) => {
  const result = loginSchema.safeParse(req.body);

  if (!result.success) {
    return res.status(400).json({ error: 'Invalid payload', details: result.error.flatten() });
  }

  const { email, password } = result.data;
  const admin = await prisma.admin.findUnique({
    where: { email },
    include: { company: true },
  });

  if (!admin || !admin.company) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const valid = await verifyPassword(password, admin.password);
  if (!valid) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const tokens = createTokenPair({
    adminId: admin.id,
    companyId: admin.companyId,
    email: admin.email,
    role: admin.role,
  });

  await prisma.refreshToken.create({
    data: {
      adminId: admin.id,
      tokenId: tokens.refreshTokenId,
      expiresAt: tokens.refreshTokenExpiresAt,
    },
  });

  return respondWithSession(res, {
    company: { id: admin.company.id, name: admin.company.name, slug: admin.company.slug },
    admin: {
      id: admin.id,
      email: admin.email,
      firstName: admin.firstName,
      lastName: admin.lastName,
      role: admin.role,
      phone: admin.phone,
    },
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    accessTokenExpiresAt: tokens.accessTokenExpiresAt,
    refreshTokenExpiresAt: tokens.refreshTokenExpiresAt,
  });
});

router.post('/refresh', async (req, res) => {
  const result = refreshSchema.safeParse(req.body);

  if (!result.success) {
    return res.status(400).json({ error: 'Invalid payload', details: result.error.flatten() });
  }

  const { refreshToken } = result.data;

  try {
    const payload = verifyRefreshToken(refreshToken);

    const stored = await prisma.refreshToken.findUnique({
      where: { tokenId: payload.tokenId },
    });

    if (!stored || stored.revoked || stored.expiresAt.getTime() < Date.now()) {
      return res.status(401).json({ error: 'Refresh token expired or revoked' });
    }

    if (stored.adminId !== payload.sub) {
      return res.status(401).json({ error: 'Refresh token invalid for this account' });
    }

    const admin = await prisma.admin.findUnique({
      where: { id: payload.sub },
      include: { company: true },
    });

    if (!admin || !admin.company) {
      return res.status(401).json({ error: 'Account not available' });
    }

    const tokens = createTokenPair({
      adminId: admin.id,
      companyId: admin.companyId,
      email: admin.email,
      role: admin.role,
    });

    await prisma.$transaction([
      prisma.refreshToken.update({
        where: { tokenId: stored.tokenId },
        data: { revoked: true },
      }),
      prisma.refreshToken.create({
        data: {
          adminId: admin.id,
          tokenId: tokens.refreshTokenId,
          expiresAt: tokens.refreshTokenExpiresAt,
        },
      }),
    ]);

    return respondWithSession(res, {
      company: { id: admin.company.id, name: admin.company.name, slug: admin.company.slug },
      admin: {
        id: admin.id,
        email: admin.email,
        firstName: admin.firstName,
        lastName: admin.lastName,
        role: admin.role,
        phone: admin.phone,
      },
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessTokenExpiresAt: tokens.accessTokenExpiresAt,
      refreshTokenExpiresAt: tokens.refreshTokenExpiresAt,
    });
  } catch (error) {
    return res.status(401).json({ error: 'Unable to refresh token', detail: (error as Error).message });
  }
});

router.get('/me', authenticate, async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const admin = await prisma.admin.findUnique({
    where: { id: req.auth.adminId },
    include: { company: true },
  });

  if (!admin || !admin.company) {
    return res.status(404).json({ error: 'Account not found' });
  }

  return res.json({
    company: { id: admin.company.id, name: admin.company.name, slug: admin.company.slug },
    admin: {
      id: admin.id,
      email: admin.email,
      firstName: admin.firstName,
      lastName: admin.lastName,
      role: admin.role,
      phone: admin.phone,
    },
  });
});

export const authRouter = router;
