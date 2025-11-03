import { Router } from 'express';
import { z } from 'zod';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';

const router = Router();

router.use(authenticate);

const createSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
});

const updateSchema = z.object({
  name: z.string().min(1).optional(),
  description: z.string().optional(),
});

const canManage = (role: UserRole) => role === UserRole.ADMIN || role === UserRole.OWNER;

router.get('/', async (_req, res) => {
  const machineTypes = await prisma.machineType.findMany({
    orderBy: { name: 'asc' },
  });
  return res.json(machineTypes);
});

router.get('/:machineTypeId', async (req, res) => {
  const { machineTypeId } = req.params;
  const machineType = await prisma.machineType.findUnique({ where: { id: machineTypeId } });
  if (!machineType) {
    return res.status(404).json({ error: 'Machine type not found' });
  }
  return res.json(machineType);
});

router.post('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to create machine types' });
  }

  const parsed = createSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  try {
    const machineType = await prisma.machineType.create({
      data: {
        name: parsed.data.name,
        description: parsed.data.description ?? null,
      },
    });
    return res.status(201).json(machineType);
  } catch (error) {
    return res.status(409).json({ error: 'Machine type name must be unique', detail: (error as Error).message });
  }
});

router.patch('/:machineTypeId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update machine types' });
  }

  const parsed = updateSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const data: { name?: string; description?: string | null } = {};
  if (parsed.data.name !== undefined) {
    data.name = parsed.data.name;
  }
  if (parsed.data.description !== undefined) {
    data.description = parsed.data.description ?? null;
  }

  try {
    const machineType = await prisma.machineType.update({
      where: { id: req.params.machineTypeId },
      data,
    });
    return res.json(machineType);
  } catch (error) {
    return res.status(404).json({ error: 'Machine type not found', detail: (error as Error).message });
  }
});

router.delete('/:machineTypeId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete machine types' });
  }

  const count = await prisma.machine.count({ where: { machineTypeId: req.params.machineTypeId } });
  if (count > 0) {
    return res.status(400).json({ error: 'Cannot delete machine type in use by machines' });
  }

  await prisma.machineType.delete({ where: { id: req.params.machineTypeId } });
  return res.status(204).send();
});

export const machineTypesRouter = router;
