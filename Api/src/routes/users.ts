import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { hashPassword } from '../lib/password.js';
import { isCompanyManager } from './helpers/authorization.js';
import { createUserSchema, updateUserSchema, userLookupSchema } from './helpers/users.js';

const router = Router();

router.use(authenticate);









// Lists company members and their roles.
router.get('/', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.json([]);
  }

  const memberships = await prisma.membership.findMany({
    where: {
      companyId: req.auth.companyId,
    },
    include: {
      user: true,
    },
    orderBy: [
      {
        user: {
          lastName: 'asc',
        },
      },
      {
        user: {
          firstName: 'asc',
        },
      },
    ],
  });
  return res.json(
    memberships.map((membership) => ({
      id: membership.user.id,
      email: membership.user.email,
      firstName: membership.user.firstName,
      lastName: membership.user.lastName,
      phone: membership.user.phone,
      role: membership.role,
      createdAt: membership.user.createdAt,
      updatedAt: membership.user.updatedAt,
    })),
  );
});

// Looks up membership details for a set of user ids.
router.post('/lookup', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.json([]);
  }

  const parsed = userLookupSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  if (parsed.data.userIds.length === 0) {
    return res.json([]);
  }

  type MembershipRow = {
    user_id: string;
    user_email: string;
    user_first_name: string;
    user_last_name: string;
    user_phone: string | null;
    membership_role: UserRole;
    user_created_at: Date;
    user_updated_at: Date;
  };

  const userIdsCsv = parsed.data.userIds.join(',');
  const rows = await prisma.$queryRaw<MembershipRow[]>(
    Prisma.sql`SELECT * FROM v_user_memberships WHERE company_id = ${req.auth.companyId} AND FIND_IN_SET(user_id, ${userIdsCsv}) > 0 ORDER BY user_last_name ASC, user_first_name ASC`,
  );

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


// Get user details by their ID`
router.get('/:userId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { userId } = req.params;
  
  if (!userId) {
    return res.status(400).json({ error: 'User ID is required' });
  }
  
  let membership = null;
  if (req.auth.companyId) {
    membership = await prisma.membership.findUnique({
      where: {
        userId_companyId: {
          userId,
          companyId: req.auth.companyId,
        },
      },
      include: { user: true },
    });
  }

  if (membership) {
    return res.json({
      id: membership.userId,
      email: membership.user?.email,
      firstName: membership.user?.firstName,
      lastName: membership.user?.lastName,
      phone: membership.user?.phone,
      role: membership.role,
      createdAt: membership.user?.createdAt,
      updatedAt: membership.user?.updatedAt,
    });
  }

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
      email: true,
      firstName: true,
      lastName: true,
      phone: true,
      createdAt: true,
      updatedAt: true,
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
    phone: user.phone,
    role: null,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
  });
});

// Invites a user to the company or attaches an existing account.
router.post('/', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to invite users' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to invite users' });
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

// Updates user profile fields or their role within the company.
router.patch('/:userId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { userId } = req.params;
  
  if (!userId) {
    return res.status(400).json({ error: 'User ID is required' });
  }
  
  const parsed = updateUserSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to update users' });
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
  if (!isSelf && !isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update other users' });
  }

  if (parsed.data.role && !isCompanyManager(req.auth.role)) {
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
  if (parsed.data.role && isCompanyManager(req.auth.role)) {
    userUpdates.role = parsed.data.role;
  }

  const membershipUpdates: Record<string, unknown> = {};
  if (parsed.data.role && isCompanyManager(req.auth.role)) {
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
              companyId: req.auth.companyId!,
            },
          },
          data: membershipUpdates,
        })
      : prisma.membership.findUnique({
          where: {
            userId_companyId: {
              userId,
              companyId: req.auth.companyId!,
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

// Removes a user from the company or deletes their account when appropriate.
router.delete('/:userId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to remove users' });
  }

  const { userId } = req.params;
  
  if (!userId) {
    return res.status(400).json({ error: 'User ID is required' });
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
  if (!isSelf && !isCompanyManager(req.auth.role)) {
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

router.get('/:userId/refresh-tokens', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to view refresh tokens' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to view refresh tokens' });
  }

  const { userId } = req.params;
  
  if (!userId) {
    return res.status(400).json({ error: 'User ID is required' });
  }

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

  const rows = await prisma.$queryRaw<RefreshTokenRow[]>(
    Prisma.sql`SELECT * FROM v_user_refresh_tokens WHERE user_id = ${userId}`,
  );

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
