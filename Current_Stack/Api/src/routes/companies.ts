import { Router } from 'express';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { isCompanyManager } from './helpers/authorization.js';
import {
  updateCompanySchema,
  toCompanyMembershipResponse,
  type CompanyMembershipRecord,
} from './helpers/companies.js';

const router = Router();

router.use(authenticate);

// Lists all companies the authenticated user belongs to.
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

  return res.json(toCompanyMembershipResponse(memberships as CompanyMembershipRecord[]));
});

// Fetches the authenticated user's membership details for a specific company.
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

// Updates metadata for the current company when requested by a manager.
router.patch('/:companyId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { companyId } = req.params;
  if (companyId !== req.auth.companyId) {
    return res.status(403).json({ error: 'Cannot modify another company' });
  }

  if (!isCompanyManager(req.auth.role)) {
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

// Permanently deletes the active company when requested by an owner.
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
