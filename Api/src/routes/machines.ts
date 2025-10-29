import { Router } from 'express';
import { z } from 'zod';
import { UserRole } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';

const router = Router();

router.use(authenticate);

const canManage = (role: UserRole) => role === UserRole.ADMIN || role === UserRole.OWNER;

const createMachineSchema = z.object({
  code: z.string().min(1),
  description: z.string().optional(),
  machineTypeId: z.string().cuid(),
  locationId: z.string().cuid().optional(),
});

const updateMachineSchema = z.object({
  code: z.string().min(1).optional(),
  description: z.string().optional(),
  machineTypeId: z.string().cuid().optional(),
  locationId: z.string().cuid().optional(),
});

const createCoilSchema = z.object({
  code: z.string().min(1),
});

const updateCoilSchema = z.object({
  code: z.string().min(1).optional(),
});

const createCoilItemSchema = z.object({
  skuId: z.string().cuid(),
  par: z.number().int().min(0),
});

const updateCoilItemSchema = z.object({
  skuId: z.string().cuid().optional(),
  par: z.number().int().min(0).optional(),
});

const ensureMachine = async (companyId: string, machineId: string) => {
  const machine = await prisma.machine.findUnique({
    where: { id: machineId },
    include: {
      machineType: true,
      location: true,
    },
  });
  if (!machine || machine.companyId !== companyId) {
    return null;
  }
  return machine;
};

const ensureCoil = async (machineId: string, coilId: string) => {
  const coil = await prisma.coil.findUnique({
    where: { id: coilId },
    include: {
      coilItems: {
        include: { sku: true },
      },
    },
  });
  if (!coil || coil.machineId !== machineId) {
    return null;
  }
  return coil;
};

const ensureCoilItem = async (coilId: string, coilItemId: string) => {
  const coilItem = await prisma.coilItem.findUnique({
    where: { id: coilItemId },
    include: { sku: true, coil: true },
  });
  if (!coilItem || coilItem.coilId !== coilId) {
    return null;
  }
  return coilItem;
};

router.get('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const machines = await prisma.machine.findMany({
    where: { companyId: req.auth.companyId },
    include: {
      machineType: true,
      location: true,
    },
    orderBy: { code: 'asc' },
  });

  return res.json(machines);
});

router.get('/details', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type MachineDetailsRow = {
    company_id: string;
    machine_id: string;
    machine_code: string;
    machine_description: string | null;
    machine_type_id: string;
    machine_type_name: string;
    machine_type_description: string | null;
    location_id: string | null;
    location_name: string | null;
    location_address: string | null;
  };

  const rowsRaw = await prisma.$queryRaw`
    SELECT *
    FROM v_machine_details
    WHERE company_id = ${req.auth.companyId}
    ORDER BY machine_code ASC
  `;
  const rows = rowsRaw as MachineDetailsRow[];

  return res.json(
    rows.map((row) => ({
      id: row.machine_id,
      code: row.machine_code,
      description: row.machine_description,
      machineType: {
        id: row.machine_type_id,
        name: row.machine_type_name,
        description: row.machine_type_description,
      },
      location: row.location_id
        ? {
            id: row.location_id,
            name: row.location_name,
            address: row.location_address,
          }
        : null,
    })),
  );
});

router.get('/coil-inventory', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type CoilInventoryRow = {
    coil_id: string;
    coil_code: string;
    machine_id: string;
    company_id: string;
    machine_code: string;
    coil_item_id: string | null;
    par_level: number | null;
    sku_id: string | null;
    sku_code: string | null;
    sku_name: string | null;
    sku_type: string | null;
    sku_is_cheese_and_crackers: number | boolean | null;
  };

  const { machineId } = req.query;

  const rowsRaw =
    typeof machineId === 'string'
      ? await prisma.$queryRaw`
          SELECT *
          FROM v_coil_inventory
          WHERE company_id = ${req.auth.companyId}
            AND machine_id = ${machineId}
          ORDER BY machine_code ASC, coil_code ASC
        `
      : await prisma.$queryRaw`
          SELECT *
          FROM v_coil_inventory
          WHERE company_id = ${req.auth.companyId}
          ORDER BY machine_code ASC, coil_code ASC
        `;

  const rows = rowsRaw as CoilInventoryRow[];

  return res.json(
    rows.map((row) => ({
      coil: {
        id: row.coil_id,
        code: row.coil_code,
      },
      machine: {
        id: row.machine_id,
        code: row.machine_code,
      },
      coilItem: row.coil_item_id
        ? {
            id: row.coil_item_id,
            par: row.par_level,
            sku: row.sku_id
              ? {
                  id: row.sku_id,
                  code: row.sku_code,
                  name: row.sku_name,
                  type: row.sku_type,
                  isCheeseAndCrackers: Boolean(row.sku_is_cheese_and_crackers),
                }
              : null,
          }
        : null,
    })),
  );
});

router.post('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to create machines' });
  }

  const parsed = createMachineSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const machineType = await prisma.machineType.findUnique({ where: { id: parsed.data.machineTypeId } });
  if (!machineType) {
    return res.status(404).json({ error: 'Machine type not found' });
  }

  let locationId: string | undefined;
  if (parsed.data.locationId) {
    const location = await prisma.location.findUnique({ where: { id: parsed.data.locationId } });
    if (!location || location.companyId !== req.auth.companyId) {
      return res.status(404).json({ error: 'Location not found for this company' });
    }
    locationId = location.id;
  }

  try {
    const machine = await prisma.machine.create({
      data: {
        companyId: req.auth.companyId,
        code: parsed.data.code,
        description: parsed.data.description ?? null,
        machineTypeId: parsed.data.machineTypeId,
        locationId,
      },
      include: {
        machineType: true,
        location: true,
      },
    });
    return res.status(201).json(machine);
  } catch (error) {
    return res.status(409).json({ error: 'Machine code must be unique per company', detail: (error as Error).message });
  }
});

router.get('/:machineId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  return res.json(machine);
});

router.patch('/:machineId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update machines' });
  }

  const parsed = updateMachineSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  if (parsed.data.machineTypeId) {
    const machineType = await prisma.machineType.findUnique({ where: { id: parsed.data.machineTypeId } });
    if (!machineType) {
      return res.status(404).json({ error: 'Machine type not found' });
    }
  }

  if (parsed.data.locationId) {
    const location = await prisma.location.findUnique({ where: { id: parsed.data.locationId } });
    if (!location || location.companyId !== req.auth.companyId) {
      return res.status(404).json({ error: 'Location not found for this company' });
    }
  }

  const data: {
    code?: string;
    description?: string | null;
    machineTypeId?: string;
    locationId?: string | null;
  } = {};

  if (parsed.data.code !== undefined) {
    data.code = parsed.data.code;
  }
  if (parsed.data.description !== undefined) {
    data.description = parsed.data.description ?? null;
  }
  if (parsed.data.machineTypeId !== undefined) {
    data.machineTypeId = parsed.data.machineTypeId;
  }
  if (parsed.data.locationId !== undefined) {
    data.locationId = parsed.data.locationId ?? null;
  }

  try {
    const updated = await prisma.machine.update({
      where: { id: machine.id },
      data,
      include: {
        machineType: true,
        location: true,
      },
    });
    return res.json(updated);
  } catch (error) {
    return res.status(409).json({ error: 'Machine code must be unique per company', detail: (error as Error).message });
  }
});

router.delete('/:machineId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete machines' });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  await prisma.machine.delete({ where: { id: machine.id } });
  return res.status(204).send();
});

router.get('/:machineId/coils', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  const coils = await prisma.coil.findMany({
    where: { machineId: machine.id },
    include: {
      coilItems: {
        include: { sku: true },
      },
    },
    orderBy: { code: 'asc' },
  });

  return res.json(coils);
});

router.post('/:machineId/coils', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to create coils' });
  }

  const parsed = createCoilSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  try {
    const coil = await prisma.coil.create({
      data: {
        machineId: machine.id,
        code: parsed.data.code,
      },
      include: {
        coilItems: true,
      },
    });
    return res.status(201).json(coil);
  } catch (error) {
    return res.status(409).json({ error: 'Coil code must be unique per machine', detail: (error as Error).message });
  }
});

router.patch('/:machineId/coils/:coilId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update coils' });
  }

  const parsed = updateCoilSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  const coil = await ensureCoil(machine.id, req.params.coilId);
  if (!coil) {
    return res.status(404).json({ error: 'Coil not found' });
  }

  const data: { code?: string } = {};
  if (parsed.data.code !== undefined) {
    data.code = parsed.data.code;
  }

  try {
    const updated = await prisma.coil.update({
      where: { id: coil.id },
      data,
      include: {
        coilItems: {
          include: { sku: true },
        },
      },
    });
    return res.json(updated);
  } catch (error) {
    return res.status(409).json({ error: 'Coil code must be unique per machine', detail: (error as Error).message });
  }
});

router.delete('/:machineId/coils/:coilId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete coils' });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  const coil = await ensureCoil(machine.id, req.params.coilId);
  if (!coil) {
    return res.status(404).json({ error: 'Coil not found' });
  }

  await prisma.coil.delete({ where: { id: coil.id } });
  return res.status(204).send();
});

router.get('/:machineId/coils/:coilId/items', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  const coil = await ensureCoil(machine.id, req.params.coilId);
  if (!coil) {
    return res.status(404).json({ error: 'Coil not found' });
  }

  return res.json(coil.coilItems);
});

router.post('/:machineId/coils/:coilId/items', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to assign coil items' });
  }

  const parsed = createCoilItemSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  const coil = await ensureCoil(machine.id, req.params.coilId);
  if (!coil) {
    return res.status(404).json({ error: 'Coil not found' });
  }

  const sku = await prisma.sKU.findUnique({ where: { id: parsed.data.skuId } });
  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }

  try {
    const coilItem = await prisma.coilItem.create({
      data: {
        coilId: coil.id,
        skuId: parsed.data.skuId,
        par: parsed.data.par,
      },
      include: { sku: true },
    });
    return res.status(201).json(coilItem);
  } catch (error) {
    return res.status(409).json({ error: 'Coil item already exists for this SKU', detail: (error as Error).message });
  }
});

router.patch('/:machineId/coils/:coilId/items/:coilItemId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update coil items' });
  }

  const parsed = updateCoilItemSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  const coil = await ensureCoil(machine.id, req.params.coilId);
  if (!coil) {
    return res.status(404).json({ error: 'Coil not found' });
  }

  const coilItem = await ensureCoilItem(coil.id, req.params.coilItemId);
  if (!coilItem) {
    return res.status(404).json({ error: 'Coil item not found' });
  }

  if (parsed.data.skuId) {
    const sku = await prisma.sKU.findUnique({ where: { id: parsed.data.skuId } });
    if (!sku) {
      return res.status(404).json({ error: 'SKU not found' });
    }
  }

  const data: { skuId?: string; par?: number } = {};
  if (parsed.data.skuId !== undefined) {
    data.skuId = parsed.data.skuId;
  }
  if (parsed.data.par !== undefined) {
    data.par = parsed.data.par;
  }

  try {
    const updated = await prisma.coilItem.update({
      where: { id: coilItem.id },
      data,
      include: { sku: true },
    });
    return res.json(updated);
  } catch (error) {
    return res.status(409).json({ error: 'Coil item already exists for this SKU', detail: (error as Error).message });
  }
});

router.delete('/:machineId/coils/:coilId/items/:coilItemId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete coil items' });
  }

  const machine = await ensureMachine(req.auth.companyId, req.params.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  const coil = await ensureCoil(machine.id, req.params.coilId);
  if (!coil) {
    return res.status(404).json({ error: 'Coil not found' });
  }

  const coilItem = await ensureCoilItem(coil.id, req.params.coilItemId);
  if (!coilItem) {
    return res.status(404).json({ error: 'Coil item not found' });
  }

  await prisma.coilItem.delete({ where: { id: coilItem.id } });
  return res.status(204).send();
});

export const machinesRouter = router;
