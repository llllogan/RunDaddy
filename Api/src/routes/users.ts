import { Router } from 'express';
import { z } from 'zod';
import { Prisma } from '@prisma/client';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { hashPassword } from '../lib/password.js';

const router = Router();

router.use(authenticate);

const createUserSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  phone: z.string().min(7).optional(),
  role: z.nativeEnum(UserRole).default(UserRole.PICKER),
});

const updateUserSchema = z.object({
  firstName: z.string().min(1).optional(),
  lastName: z.string().min(1).optional(),
  phone: z.string().optional(),
  password: z.string().min(8).optional(),
  role: z.nativeEnum(UserRole).optional(),
});

const canManageUsers = (role: UserRole) => role === UserRole.ADMIN || role === UserRole.OWNER;

const extractRows = <T>(result: unknown): T[] => {
  if (Array.isArray(result)) {
    if (result.length > 0 && Array.isArray(result[0])) {
      return result[0] as T[];
    }
    return result as T[];
  }
  return [];
};

router.get('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type UserMembershipRow = {
    user_id: string;
    user_email: string;
    user_first_name: string;
    user_last_name: string;
    user_phone: string | null;
    user_created_at: Date;
    user_updated_at: Date;
    user_role: UserRole;
    membership_role: UserRole;
    company_id: string;
  };

  const rowsRaw = await prisma.$queryRaw<UserMembershipRow[][]>(
    Prisma.sql`CALL sp_get_user_memberships(${req.auth.companyId})`,
  );
  const rows = extractRows<UserMembershipRow>(rowsRaw);

  return res.json(
    rows.map((row) => ({
      id: row.user_id,
      email: row.user_email,
      firstName: row.user_first_name,
      lastName: row.user_last_name,
      phone: row.user_phone,
      role: row.membership_role,
      createdAt: row.user_created_at,
      updatedAt: row.user_updated_at,
    })),
  );
});

router.get('/:userId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { userId } = req.params;
  const membership = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId,
        companyId: req.auth.companyId,
      },
    },
    include: { user: true },
  });

  if (!membership) {
    return res.status(404).json({ error: 'User not found in this company' });
  }

  return res.json({
    id: membership.user.id,
    email: membership.user.email,
    firstName: membership.user.firstName,
    lastName: membership.user.lastName,
    phone: membership.user.phone,
    role: membership.role,
    createdAt: membership.user.createdAt,
    updatedAt: membership.user.updatedAt,
  });
});

router.post('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManageUsers(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to invite users' });
  }

  const parsed = createUserSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { email, password, firstName, lastName, phone, role } = parsed.data;

  const existingUser = await prisma.user.findUnique({ where: { email } });

  if (existingUser) {
    const membership = await prisma.membership.findUnique({
      where: {
        userId_companyId: {
          userId: existingUser.id,
          companyId: req.auth.companyId,
        },
      },
    });

    if (membership) {
      return res.status(409).json({ error: 'User already belongs to this company' });
    }

    const createdMembership = await prisma.membership.create({
      data: {
        userId: existingUser.id,
        companyId: req.auth.companyId,
        role,
      },
    });

    return res.status(201).json({
      id: existingUser.id,
      email: existingUser.email,
      firstName: existingUser.firstName,
      lastName: existingUser.lastName,
      phone: existingUser.phone,
      role: createdMembership.role,
      createdAt: existingUser.createdAt,
      updatedAt: existingUser.updatedAt,
    });
  }

  const passwordHash = await hashPassword(password);

  const user = await prisma.user.create({
    data: {
      email,
      password: passwordHash,
      firstName,
      lastName,
      phone: phone ?? null,
      role,
    },
  });

  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: req.auth.companyId,
      role,
    },
  });
  await prisma.user.update({
    where: { id: user.id },
    data: { defaultMembershipId: membership.id },
  });

  return res.status(201).json({
    id: user.id,
    email: user.email,
    firstName: user.firstName,
    lastName: user.lastName,
    phone: user.phone,
    role: membership.role,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
  });
});

router.patch('/:userId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { userId } = req.params;
  const parsed = updateUserSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const membership = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId,
        companyId: req.auth.companyId,
      },
    },
    include: { user: true },
  });

  if (!membership) {
    return res.status(404).json({ error: 'User not found in this company' });
  }

  const isSelf = req.auth.userId === userId;
  if (!isSelf && !canManageUsers(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update other users' });
  }

  if (parsed.data.role && !canManageUsers(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to change roles' });
  }

  const userUpdates: Record<string, unknown> = {};
  if (parsed.data.firstName !== undefined) {
    userUpdates.firstName = parsed.data.firstName;
  }
  if (parsed.data.lastName !== undefined) {
    userUpdates.lastName = parsed.data.lastName;
  }
  if (parsed.data.phone !== undefined) {
    userUpdates.phone = parsed.data.phone ?? null;
  }
  if (parsed.data.password) {
    userUpdates.password = await hashPassword(parsed.data.password);
  }
  if (parsed.data.role && canManageUsers(req.auth.role)) {
    userUpdates.role = parsed.data.role;
  }

  const membershipUpdates: Record<string, unknown> = {};
  if (parsed.data.role && canManageUsers(req.auth.role)) {
    membershipUpdates.role = parsed.data.role;
  }

  const [updatedUser, updatedMembership] = await prisma.$transaction([
    Object.keys(userUpdates).length
      ? prisma.user.update({ where: { id: userId }, data: userUpdates })
      : prisma.user.findUnique({ where: { id: userId } }),
    Object.keys(membershipUpdates).length
      ? prisma.membership.update({
          where: {
            userId_companyId: {
              userId,
              companyId: req.auth.companyId,
            },
          },
          data: membershipUpdates,
        })
      : prisma.membership.findUnique({
          where: {
            userId_companyId: {
              userId,
              companyId: req.auth.companyId,
            },
          },
        }),
  ]);

  if (!updatedUser || !updatedMembership) {
    return res.status(500).json({ error: 'Failed to update user' });
  }

  return res.json({
    id: updatedUser.id,
    email: updatedUser.email,
    firstName: updatedUser.firstName,
    lastName: updatedUser.lastName,
    phone: updatedUser.phone,
    role: updatedMembership.role,
    createdAt: updatedUser.createdAt,
    updatedAt: updatedUser.updatedAt,
  });
});

router.delete('/:userId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { userId } = req.params;
  const membership = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId,
        companyId: req.auth.companyId,
      },
    },
    include: { user: true },
  });

  if (!membership) {
    return res.status(404).json({ error: 'User not found in this company' });
  }

  const isSelf = req.auth.userId === userId;
  if (!isSelf && !canManageUsers(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to remove users' });
  }

  await prisma.membership.delete({
    where: {
      userId_companyId: {
        userId,
        companyId: req.auth.companyId,
      },
    },
  });

  const remainingMemberships = await prisma.membership.count({ where: { userId } });
  if (remainingMemberships === 0) {
    await prisma.$transaction([
      prisma.refreshToken.deleteMany({ where: { userId } }),
      prisma.user.delete({ where: { id: userId } }),
    ]);
  }

  return res.status(204).send();
});

router.get('/:userId/refresh-tokens', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManageUsers(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to view refresh tokens' });
  }

  const { userId } = req.params;

  const membership = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId,
        companyId: req.auth.companyId,
      },
    },
  });

  if (!membership) {
    return res.status(404).json({ error: 'User not found in this company' });
  }

  type RefreshTokenRow = {
    refresh_token_id: string;
    user_id: string;
    token_identifier: string;
    expires_at: Date;
    is_revoked: number | boolean;
    created_at: Date;
    token_context: string;
  };

  const rowsRaw = await prisma.$queryRaw<RefreshTokenRow[][]>(
    Prisma.sql`CALL sp_get_user_refresh_tokens(${userId})`,
  );
  const rows = extractRows<RefreshTokenRow>(rowsRaw);

  return res.json(
    rows.map((row) => ({
      id: row.refresh_token_id,
      tokenId: row.token_identifier,
      expiresAt: row.expires_at,
      revoked: Boolean(row.is_revoked),
      createdAt: row.created_at,
      context: row.token_context,
    })),
  );
});

export const usersRouter = router;
