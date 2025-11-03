import { Router } from 'express';
import { z } from 'zod';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';

const router = Router();

router.use(authenticate);

const createSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  type: z.string().min(1),
  isCheeseAndCrackers: z.boolean().optional(),
});

const updateSchema = z.object({
  code: z.string().min(1).optional(),
  name: z.string().min(1).optional(),
  type: z.string().min(1).optional(),
  isCheeseAndCrackers: z.boolean().optional(),
});

const canManage = (role: UserRole) => role === UserRole.ADMIN || role === UserRole.OWNER;

router.get('/', async (_req, res) => {
  const skus = await prisma.sKU.findMany({ orderBy: { name: 'asc' } });
  return res.json(skus);
});

router.get('/:skuId', async (req, res) => {
  const sku = await prisma.sKU.findUnique({ where: { id: req.params.skuId } });
  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }
  return res.json(sku);
});

router.post('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to create SKUs' });
  }

  const parsed = createSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  try {
    const sku = await prisma.sKU.create({
      data: {
        code: parsed.data.code,
        name: parsed.data.name,
        type: parsed.data.type,
        isCheeseAndCrackers: parsed.data.isCheeseAndCrackers ?? false,
      },
    });
    return res.status(201).json(sku);
  } catch (error) {
    return res.status(409).json({ error: 'SKU code must be unique', detail: (error as Error).message });
  }
});

router.patch('/:skuId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKUs' });
  }

  const parsed = updateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const data: {
    code?: string;
    name?: string;
    type?: string;
    isCheeseAndCrackers?: boolean;
  } = {};

  if (parsed.data.code !== undefined) {
    data.code = parsed.data.code;
  }
  if (parsed.data.name !== undefined) {
    data.name = parsed.data.name;
  }
  if (parsed.data.type !== undefined) {
    data.type = parsed.data.type;
  }
  if (parsed.data.isCheeseAndCrackers !== undefined) {
    data.isCheeseAndCrackers = parsed.data.isCheeseAndCrackers;
  }

  try {
    const sku = await prisma.sKU.update({
      where: { id: req.params.skuId },
      data,
    });
    return res.json(sku);
  } catch (error) {
    return res.status(404).json({ error: 'SKU not found', detail: (error as Error).message });
  }
});

router.delete('/:skuId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete SKUs' });
  }

  const count = await prisma.coilItem.count({ where: { skuId: req.params.skuId } });
  if (count > 0) {
    return res.status(400).json({ error: 'Cannot delete SKU assigned to coil items' });
  }

  await prisma.sKU.delete({ where: { id: req.params.skuId } });
  return res.status(204).send();
});

export const skusRouter = router;
