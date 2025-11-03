import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { hashPassword } from '../lib/password.js';
import { UserRole } from '../types/enums.js';
import {
  createCompanySchema,
  createUserSchema,
  createMembershipSchema,
} from './helpers/debug.js';

const router = Router();

// Creates a company without authentication for local testing purposes.
router.post('/companies', async (req, res) => {
  const parsed = createCompanySchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const company = await prisma.company.create({
    data: {
      name: parsed.data.name,
    },
  });

  return res.status(201).json(company);
});

// Deletes a company record by id, ignoring membership requirements.
router.delete('/companies/:companyId', async (req, res) => {
  const { companyId } = req.params;

  try {
    await prisma.company.delete({ where: { id: companyId } });
    return res.status(204).send();
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
      return res.status(404).json({ error: 'Company not found' });
    }
    throw error;
  }
});

// Lists all companies currently stored in the database.
router.get('/companies', async (_req, res) => {
  const companies = await prisma.company.findMany({
    orderBy: { createdAt: 'desc' },
  });
  return res.json(companies);
});

// Returns machine details for a company including coils and SKUs.
router.get('/companies/:companyId/machines', async (req, res) => {
  const { companyId } = req.params;

  const company = await prisma.company.findUnique({
    where: { id: companyId },
    select: { id: true },
  });

  if (!company) {
    return res.status(404).json({ error: 'Company not found' });
  }

  const machines = await prisma.machine.findMany({
    where: { companyId },
    include: {
      machineType: {
        select: {
          id: true,
          name: true,
          description: true,
        },
      },
      location: {
        select: {
          id: true,
          name: true,
          address: true,
        },
      },
      coils: {
        orderBy: { code: 'asc' },
        select: {
          id: true,
          code: true,
          coilItems: {
            orderBy: { sku: { code: 'asc' } },
            select: {
              id: true,
              par: true,
              sku: {
                select: {
                  id: true,
                  code: true,
                  name: true,
                  type: true,
                },
              },
            },
          },
        },
      },
    },
    orderBy: [{ code: 'asc' }],
  });

  return res.json(
    machines.map((machine) => ({
      id: machine.id,
      code: machine.code,
      description: machine.description,
      machineType: machine.machineType,
      location: machine.location,
      coils: machine.coils.map((coil) => ({
        id: coil.id,
        code: coil.code,
        items: coil.coilItems.map((item) => ({
          id: item.id,
          par: item.par,
          sku: item.sku,
        })),
      })),
    })),
  );
});

// Creates a user and optional membership for debugging workflows.
router.post('/users', async (req, res) => {
  const parsed = createUserSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { email, password, firstName, lastName, phone, role, companyId, membershipRole, setAsDefaultMembership } =
    parsed.data;

  const existingUser = await prisma.user.findUnique({ where: { email } });
  if (existingUser) {
    return res.status(409).json({ error: 'Email already registered' });
  }

  if (companyId) {
    const company = await prisma.company.findUnique({ where: { id: companyId } });
    if (!company) {
      return res.status(404).json({ error: 'Company not found' });
    }
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

  let membership: { id: string; companyId: string; role: UserRole } | null = null;

  if (companyId) {
    membership = await prisma.membership.create({
      data: {
        userId: user.id,
        companyId,
        role: membershipRole ?? role,
      },
      select: {
        id: true,
        companyId: true,
        role: true,
      },
    });

    if (setAsDefaultMembership ?? true) {
      await prisma.user.update({
        where: { id: user.id },
        data: { defaultMembershipId: membership.id },
      });
    }
  }

  return res.status(201).json({
    user: {
      id: user.id,
      email: user.email,
      firstName: user.firstName,
      lastName: user.lastName,
      phone: user.phone,
      role: user.role,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    },
    membership,
  });
});

// Deletes a user by id without enforcing company constraints.
router.delete('/users/:userId', async (req, res) => {
  const { userId } = req.params;

  try {
    await prisma.user.delete({ where: { id: userId } });
    return res.status(204).send();
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
      return res.status(404).json({ error: 'User not found' });
    }
    throw error;
  }
});

// Lists every user along with their memberships for inspection.
router.get('/users', async (_req, res) => {
  const users = await prisma.user.findMany({
    orderBy: { createdAt: 'desc' },
    include: {
      memberships: {
        select: {
          id: true,
          companyId: true,
          role: true,
        },
      },
    },
  });

  return res.json(
    users.map((user) => ({
      id: user.id,
      email: user.email,
      firstName: user.firstName,
      lastName: user.lastName,
      phone: user.phone,
      role: user.role,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      memberships: user.memberships,
    })),
  );
});

// Creates a membership between an existing user and company.
router.post('/memberships', async (req, res) => {
  const parsed = createMembershipSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { userId, companyId, role, setAsDefault } = parsed.data;

  const [user, company] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { id: true } }),
    prisma.company.findUnique({ where: { id: companyId }, select: { id: true } }),
  ]);

  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  if (!company) {
    return res.status(404).json({ error: 'Company not found' });
  }

  try {
    const membership = await prisma.membership.create({
      data: {
        userId,
        companyId,
        role,
      },
      select: {
        id: true,
        userId: true,
        companyId: true,
        role: true,
      },
    });

    if (setAsDefault ?? false) {
      await prisma.user.update({
        where: { id: userId },
        data: { defaultMembershipId: membership.id },
      });
    }

    return res.status(201).json(membership);
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      return res.status(409).json({ error: 'Membership already exists for this user and company' });
    }
    throw error;
  }
});

// Removes a membership by id regardless of authentication.
router.delete('/memberships/:membershipId', async (req, res) => {
  const { membershipId } = req.params;

  try {
    await prisma.membership.delete({ where: { id: membershipId } });
    return res.status(204).send();
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
      return res.status(404).json({ error: 'Membership not found' });
    }
    throw error;
  }
});

// Lists memberships for a specific user, including company names.
router.get('/memberships', async (req, res) => {
  const userId = typeof req.query.userId === 'string' ? req.query.userId : null;

  if (!userId) {
    return res.status(400).json({ error: 'Query parameter "userId" is required' });
  }

  const memberships = await prisma.membership.findMany({
    where: { userId },
    include: {
      company: {
        select: {
          id: true,
          name: true,
        },
      },
    },
    orderBy: {
      company: {
        name: 'asc',
      },
    },
  });

  return res.json(
    memberships.map((membership) => ({
      id: membership.id,
      userId: membership.userId,
      companyId: membership.companyId,
      role: membership.role,
      companyName: membership.company.name,
    })),
  );
});

export const debugRouter = router;
