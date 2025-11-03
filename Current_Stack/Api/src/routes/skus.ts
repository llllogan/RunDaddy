import { Router } from 'express';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { isCompanyManager } from './helpers/authorization.js';
import { createSkuSchema, updateSkuSchema } from './helpers/skus.js';

const router = Router();

router.use(authenticate);

// Lists all SKUs in alphabetical order.
router.get('/', async (_req, res) => {
  const skus = await prisma.sKU.findMany({ orderBy: { name: 'asc' } });
  return res.json(skus);
});

// Fetches a SKU by id.
router.get('/:skuId', async (req, res) => {
  const sku = await prisma.sKU.findUnique({ where: { id: req.params.skuId } });
  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }
  return res.json(sku);
});

// Creates a new SKU record for the catalog.
router.post('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to create SKUs' });
  }

  const parsed = createSkuSchema.safeParse(req.body);
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

// Updates SKU metadata when requested by a manager.
router.patch('/:skuId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKUs' });
  }

  const parsed = updateSkuSchema.safeParse(req.body);
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

// Deletes a SKU that is not currently assigned to coil items.
router.delete('/:skuId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!isCompanyManager(req.auth.role)) {
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
