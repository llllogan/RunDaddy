import { Router } from 'express';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { isCompanyManager } from './helpers/authorization.js';
import { createLocationSchema, updateLocationSchema } from './helpers/locations.js';

const router = Router();

router.use(authenticate);

// Lists all locations belonging to the authenticated company.
router.get('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const locations = await prisma.location.findMany({
    where: { companyId: req.auth.companyId },
    orderBy: { name: 'asc' },
  });

  return res.json(locations);
});

// Fetches a single location ensuring it belongs to the active company.
router.get('/:locationId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const location = await prisma.location.findUnique({ where: { id: req.params.locationId } });
  if (!location || location.companyId !== req.auth.companyId) {
    return res.status(404).json({ error: 'Location not found' });
  }

  return res.json(location);
});

// Creates a new location for the active company.
router.post('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to create locations' });
  }

  const parsed = createLocationSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const location = await prisma.location.create({
    data: {
      companyId: req.auth.companyId,
      name: parsed.data.name,
      address: parsed.data.address ?? null,
    },
  });

  return res.status(201).json(location);
});

// Updates an existing location when requested by a company manager.
router.patch('/:locationId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update locations' });
  }

  const parsed = updateLocationSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const location = await prisma.location.findUnique({ where: { id: req.params.locationId } });
  if (!location || location.companyId !== req.auth.companyId) {
    return res.status(404).json({ error: 'Location not found' });
  }

  const data: { name?: string; address?: string | null } = {};
  if (parsed.data.name !== undefined) {
    data.name = parsed.data.name;
  }
  if (parsed.data.address !== undefined) {
    data.address = parsed.data.address ?? null;
  }

  const updated = await prisma.location.update({
    where: { id: location.id },
    data,
  });

  return res.json(updated);
});

// Deletes a location if it is unused by any machines.
router.delete('/:locationId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete locations' });
  }

  const location = await prisma.location.findUnique({ where: { id: req.params.locationId } });
  if (!location || location.companyId !== req.auth.companyId) {
    return res.status(404).json({ error: 'Location not found' });
  }

  const count = await prisma.machine.count({ where: { locationId: location.id } });
  if (count > 0) {
    return res.status(400).json({ error: 'Cannot delete location assigned to machines' });
  }

  await prisma.location.delete({ where: { id: location.id } });
  return res.status(204).send();
});

export const locationsRouter = router;
