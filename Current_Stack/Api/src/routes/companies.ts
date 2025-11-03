import { Router } from 'express';
import { z } from 'zod';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';

const router = Router();

router.use(authenticate);

const updateCompanySchema = z.object({
  name: z.string().min(1),
});

router.get('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const memberships = await prisma.membership.findMany({
    where: { userId: req.auth.userId },
    include: {
      company: true,
    },
    orderBy: { company: { name: 'asc' } },
  });

  type MembershipRecord = {
    company: { id: string; name: string; createdAt: Date; updatedAt: Date };
    role: UserRole;
  };

  const response = (memberships as MembershipRecord[]).map((membership) => ({
    company: {
      id: membership.company.id,
      name: membership.company.name,
      createdAt: membership.company.createdAt,
      updatedAt: membership.company.updatedAt,
    },
    role: membership.role,
  }));

  return res.json(response);
});

router.get('/:companyId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { companyId } = req.params;
  const membership = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId: req.auth.userId,
        companyId,
      },
    },
    include: { company: true },
  });

  if (!membership) {
    return res.status(404).json({ error: 'Company not found' });
  }

  return res.json({
    company: {
      id: membership.company.id,
      name: membership.company.name,
      createdAt: membership.company.createdAt,
      updatedAt: membership.company.updatedAt,
    },
    role: membership.role,
  });
});

router.patch('/:companyId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { companyId } = req.params;
  if (companyId !== req.auth.companyId) {
    return res.status(403).json({ error: 'Cannot modify another company' });
  }

  const allowedRoles = new Set<UserRole>([UserRole.ADMIN, UserRole.OWNER]);
  if (!allowedRoles.has(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update company' });
  }

  const parsed = updateCompanySchema.safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const company = await prisma.company.update({
    where: { id: companyId },
    data: {
      name: parsed.data.name,
      updatedAt: new Date(),
    },
  });

  return res.json({
    id: company.id,
    name: company.name,
    createdAt: company.createdAt,
    updatedAt: company.updatedAt,
  });
});

router.delete('/:companyId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { companyId } = req.params;
  if (companyId !== req.auth.companyId) {
    return res.status(403).json({ error: 'Cannot delete another company' });
  }

  if (req.auth.role !== UserRole.OWNER) {
    return res.status(403).json({ error: 'Only owners can delete a company' });
  }

  await prisma.company.delete({ where: { id: companyId } });
  return res.status(204).send();
});

export const companiesRouter = router;
