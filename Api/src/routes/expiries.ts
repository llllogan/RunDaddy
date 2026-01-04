import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { requireCompanyContext } from '../middleware/requireCompany.js';
import { setLogConfig } from '../middleware/logging.js';
import { buildUpcomingExpiringItems } from './helpers/expiring-items.js';

const router = Router();

router.use(authenticate, requireCompanyContext());

const upcomingQuerySchema = z.object({
  daysAhead: z.coerce.number().int().min(0).max(28).optional(),
});

const ignoreBodySchema = z.object({
  coilItemId: z.string().trim().min(1),
  expiryDate: z.string().trim().regex(/^\d{4}-\d{2}-\d{2}$/),
  quantity: z.coerce.number().int().positive(),
});

const ignoreDeleteSchema = z.object({
  coilItemId: z.coerce.string().trim().min(1),
  expiryDate: z.coerce.string().trim().regex(/^\d{4}-\d{2}-\d{2}$/),
});

router.get('/', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const parsedQuery = upcomingQuerySchema.safeParse(req.query);
  if (!parsedQuery.success) {
    return res.status(400).json({ error: 'Invalid filters supplied', details: parsedQuery.error.flatten() });
  }

  const companyId = req.auth.companyId as string;
  const response = await buildUpcomingExpiringItems({
    companyId,
    daysAhead: parsedQuery.data.daysAhead ?? 14,
  });

  return res.json(response);
});

router.post('/ignore', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const parsed = ignoreBodySchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid ignore payload', details: parsed.error.flatten() });
  }

  const companyId = req.auth.companyId as string;
  const { coilItemId, expiryDate, quantity } = parsed.data;

  const coilItem = await prisma.coilItem.findFirst({
    where: {
      id: coilItemId,
      coil: {
        machine: {
          companyId,
        },
      },
    },
    select: { id: true },
  });

  if (!coilItem) {
    return res.status(404).json({ error: 'Coil item not found' });
  }

  await prisma.expiryIgnore.upsert({
    where: {
      companyId_coilItemId_expiryDate: {
        companyId,
        coilItemId,
        expiryDate,
      },
    },
    update: {
      quantity,
      ignoredAt: new Date(),
      createdBy: req.auth.userId ?? null,
    },
    create: {
      companyId,
      coilItemId,
      expiryDate,
      quantity,
      createdBy: req.auth.userId ?? null,
    },
  });

  return res.status(204).send();
});

router.delete('/ignore', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const parsed = ignoreDeleteSchema.safeParse({ ...req.query, ...req.body });
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid ignore request', details: parsed.error.flatten() });
  }

  const companyId = req.auth.companyId as string;

  await prisma.expiryIgnore.deleteMany({
    where: {
      companyId,
      coilItemId: parsed.data.coilItemId,
      expiryDate: parsed.data.expiryDate,
    },
  });

  return res.status(204).send();
});

export { router as expiriesRouter };
