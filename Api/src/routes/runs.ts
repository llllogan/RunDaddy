import { Router } from 'express';
import { z } from 'zod';
import { Prisma } from '@prisma/client';
import { RunItemStatus, RunStatus, UserRole, isRunStatus } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';

const router = Router();

router.use(authenticate);

const canManage = (role: UserRole) => role === UserRole.ADMIN || role === UserRole.OWNER;

const extractRows = <T>(result: unknown): T[] => {
  if (Array.isArray(result)) {
    if (result.length > 0 && Array.isArray(result[0])) {
      return result[0] as T[];
    }
    return result as T[];
  }
  return [];
};

const createRunSchema = z.object({
  pickerId: z.string().cuid().optional(),
  runnerId: z.string().cuid().optional(),
  status: z.nativeEnum(RunStatus).optional(),
  pickingStartedAt: z.coerce.date().optional(),
  pickingEndedAt: z.coerce.date().optional(),
  scheduledFor: z.coerce.date().optional(),
});

const updateRunSchema = createRunSchema.partial();

const createPickEntrySchema = z.object({
  coilItemId: z.string().cuid(),
  count: z.number().int().min(0),
  status: z.nativeEnum(RunItemStatus).optional(),
  pickedAt: z.coerce.date().optional(),
});

const updatePickEntrySchema = createPickEntrySchema.partial();

const createChocolateBoxSchema = z.object({
  machineId: z.string().cuid(),
  number: z.number().int().min(1),
});

const updateChocolateBoxSchema = z.object({
  machineId: z.string().cuid().optional(),
  number: z.number().int().min(1).optional(),
});

const ensureMembership = async (companyId: string, userId: string | undefined | null) => {
  if (!userId) {
    return null;
  }
  const membership = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId,
        companyId,
      },
    },
    include: {
      user: true,
    },
  });
  return membership;
};

const ensureRun = async (companyId: string, runId: string) => {
  const run = await prisma.run.findUnique({
    where: { id: runId },
    include: {
      picker: true,
      runner: true,
      pickEntries: {
        include: {
          coilItem: {
            include: {
              sku: true,
              coil: {
                include: {
                  machine: true,
                },
              },
            },
          },
        },
      },
      chocolateBoxes: {
        include: {
          machine: true,
        },
      },
    },
  });
  if (!run || run.companyId !== companyId) {
    return null;
  }
  return run;
};

const ensureCoilItem = async (companyId: string, coilItemId: string) => {
  const coilItem = await prisma.coilItem.findUnique({
    where: { id: coilItemId },
    include: {
      coil: {
        include: {
          machine: true,
        },
      },
      sku: true,
    },
  });
  if (!coilItem || coilItem.coil.machine.companyId !== companyId) {
    return null;
  }
  return coilItem;
};

const ensureMachine = async (companyId: string, machineId: string) => {
  const machine = await prisma.machine.findUnique({ where: { id: machineId } });
  if (!machine || machine.companyId !== companyId) {
    return null;
  }
  return machine;
};

router.get('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { status } = req.query;
  const where: { companyId: string; status?: RunStatus } = { companyId: req.auth.companyId };
  if (isRunStatus(status)) {
    where.status = status;
  }

  const runs = await prisma.run.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    include: {
      picker: true,
      runner: true,
    },
  });

  return res.json(runs);
});

router.get('/overview', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { status } = req.query;
  const statusFilter = isRunStatus(status) ? status : null;

  const runs = await prisma.run.findMany({
    where: {
      companyId: req.auth.companyId,
      ...(statusFilter ? { status: statusFilter } : {}),
    },
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      pickerId: true,
      runnerId: true,
      companyId: true,
      status: true,
      pickingStartedAt: true,
      pickingEndedAt: true,
      scheduledFor: true,
      createdAt: true,
    },
  });

  return res.json(runs);
});

router.get('/pick-entries', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type RunPickEntryRow = {
    pick_entry_id: string;
    run_id: string;
    coil_item_id: string;
    picked_count: number;
    pick_status: RunItemStatus;
    picked_at: Date | null;
    coil_id: string;
    machine_id: string;
    machine_code: string;
    sku_id: string | null;
    sku_code: string | null;
    sku_name: string | null;
  };

  const { runId } = req.query;

  const runIdParam = typeof runId === 'string' ? runId : null;
  const rowsRaw = await prisma.$queryRaw<RunPickEntryRow[][]>(
    Prisma.sql`CALL sp_get_run_pick_entries(${req.auth.companyId}, ${runIdParam})`,
  );
  const rows = extractRows<RunPickEntryRow>(rowsRaw);

  return res.json(
    rows.map((row) => ({
      id: row.pick_entry_id,
      runId: row.run_id,
      coilItemId: row.coil_item_id,
      count: row.picked_count,
      status: row.pick_status,
      pickedAt: row.picked_at,
      machine: {
        id: row.machine_id,
        code: row.machine_code,
      },
      sku: row.sku_id
        ? {
            id: row.sku_id,
            code: row.sku_code,
            name: row.sku_name,
          }
        : null,
    })),
  );
});

router.get('/chocolate-boxes', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type ChocolateBoxRow = {
    chocolate_box_id: string;
    chocolate_box_number: number;
    run_id: string;
    machine_id: string;
    machine_code: string;
    run_status: RunStatus;
    scheduled_for: Date | null;
  };

  const { runId } = req.query;

  const runIdParam = typeof runId === 'string' ? runId : null;
  const rowsRaw = await prisma.$queryRaw<ChocolateBoxRow[][]>(
    Prisma.sql`CALL sp_get_chocolate_box_details(${req.auth.companyId}, ${runIdParam})`,
  );
  const rows = extractRows<ChocolateBoxRow>(rowsRaw);

  return res.json(
    rows.map((row) => ({
      id: row.chocolate_box_id,
      number: row.chocolate_box_number,
      runId: row.run_id,
      machine: {
        id: row.machine_id,
        code: row.machine_code,
      },
      runStatus: row.run_status,
      scheduledFor: row.scheduled_for,
    })),
  );
});

router.post('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to create runs' });
  }

  const parsed = createRunSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { pickerId, runnerId, status, pickingStartedAt, pickingEndedAt, scheduledFor } = parsed.data;

  if (pickerId) {
    const membership = await ensureMembership(req.auth.companyId, pickerId);
    if (!membership) {
      return res.status(404).json({ error: 'Picker not found in company' });
    }
  }

  if (runnerId) {
    const membership = await ensureMembership(req.auth.companyId, runnerId);
    if (!membership) {
      return res.status(404).json({ error: 'Runner not found in company' });
    }
  }

  const run = await prisma.run.create({
    data: {
      companyId: req.auth.companyId,
      pickerId: pickerId ?? null,
      runnerId: runnerId ?? null,
      status: status ?? RunStatus.DRAFT,
      pickingStartedAt: pickingStartedAt ?? null,
      pickingEndedAt: pickingEndedAt ?? null,
      scheduledFor: scheduledFor ?? null,
    },
    include: {
      picker: true,
      runner: true,
      pickEntries: {
        include: {
          coilItem: {
            include: {
              sku: true,
              coil: { include: { machine: true } },
            },
          },
        },
      },
      chocolateBoxes: {
        include: {
          machine: true,
        },
      },
    },
  });

  return res.status(201).json(run);
});

router.get('/:runId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  return res.json(run);
});

router.patch('/:runId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update runs' });
  }

  const parsed = updateRunSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  if (parsed.data.pickerId) {
    const membership = await ensureMembership(req.auth.companyId, parsed.data.pickerId);
    if (!membership) {
      return res.status(404).json({ error: 'Picker not found in company' });
    }
  }

  if (parsed.data.runnerId) {
    const membership = await ensureMembership(req.auth.companyId, parsed.data.runnerId);
    if (!membership) {
      return res.status(404).json({ error: 'Runner not found in company' });
    }
  }

  const data: {
    pickerId?: string | null;
    runnerId?: string | null;
    status?: RunStatus;
    pickingStartedAt?: Date | null;
    pickingEndedAt?: Date | null;
    scheduledFor?: Date | null;
  } = {};

  if (parsed.data.pickerId !== undefined) {
    data.pickerId = parsed.data.pickerId ?? null;
  }
  if (parsed.data.runnerId !== undefined) {
    data.runnerId = parsed.data.runnerId ?? null;
  }
  if (parsed.data.status !== undefined) {
    data.status = parsed.data.status;
  }
  if (parsed.data.pickingStartedAt !== undefined) {
    data.pickingStartedAt = parsed.data.pickingStartedAt ?? null;
  }
  if (parsed.data.pickingEndedAt !== undefined) {
    data.pickingEndedAt = parsed.data.pickingEndedAt ?? null;
  }
  if (parsed.data.scheduledFor !== undefined) {
    data.scheduledFor = parsed.data.scheduledFor ?? null;
  }

  const updated = await prisma.run.update({
    where: { id: run.id },
    data,
    include: {
      picker: true,
      runner: true,
      pickEntries: {
        include: {
          coilItem: {
            include: {
              sku: true,
              coil: { include: { machine: true } },
            },
          },
        },
      },
      chocolateBoxes: {
        include: {
          machine: true,
        },
      },
    },
  });

  return res.json(updated);
});

router.delete('/:runId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete runs' });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  await prisma.run.delete({ where: { id: run.id } });
  return res.status(204).send();
});

router.get('/:runId/pick-entries', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  return res.json(run.pickEntries);
});

router.post('/:runId/pick-entries', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to create pick entries' });
  }

  const parsed = createPickEntrySchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const coilItem = await ensureCoilItem(req.auth.companyId, parsed.data.coilItemId);
  if (!coilItem) {
    return res.status(404).json({ error: 'Coil item not found for this company' });
  }

  try {
    const pickEntry = await prisma.pickEntry.create({
      data: {
        runId: run.id,
        coilItemId: coilItem.id,
        count: parsed.data.count,
        status: parsed.data.status ?? RunItemStatus.PENDING,
        pickedAt: parsed.data.pickedAt ?? null,
      },
      include: {
        coilItem: {
          include: {
            sku: true,
            coil: { include: { machine: true } },
          },
        },
      },
    });
    return res.status(201).json(pickEntry);
  } catch (error) {
    return res.status(409).json({ error: 'Pick entry already exists for this coil item', detail: (error as Error).message });
  }
});

router.patch('/:runId/pick-entries/:pickEntryId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update pick entries' });
  }

  const parsed = updatePickEntrySchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const pickEntry = await prisma.pickEntry.findUnique({
    where: { id: req.params.pickEntryId },
    include: {
      coilItem: {
        include: {
          coil: {
            include: { machine: true },
          },
          sku: true,
        },
      },
    },
  });

  if (!pickEntry || pickEntry.runId !== run.id || pickEntry.coilItem.coil.machine.companyId !== req.auth.companyId) {
    return res.status(404).json({ error: 'Pick entry not found' });
  }

  const data: {
    coilItemId?: string;
    count?: number;
    status?: RunItemStatus;
    pickedAt?: Date | null;
  } = {};

  if (parsed.data.coilItemId !== undefined) {
    const coilItem = await ensureCoilItem(req.auth.companyId, parsed.data.coilItemId);
    if (!coilItem) {
      return res.status(404).json({ error: 'Coil item not found for this company' });
    }
    data.coilItemId = parsed.data.coilItemId;
  }
  if (parsed.data.count !== undefined) {
    data.count = parsed.data.count;
  }
  if (parsed.data.status !== undefined) {
    data.status = parsed.data.status;
  }
  if (parsed.data.pickedAt !== undefined) {
    data.pickedAt = parsed.data.pickedAt ?? null;
  }

  const updated = await prisma.pickEntry.update({
    where: { id: pickEntry.id },
    data,
    include: {
      coilItem: {
        include: {
          sku: true,
          coil: { include: { machine: true } },
        },
      },
    },
  });

  return res.json(updated);
});

router.delete('/:runId/pick-entries/:pickEntryId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete pick entries' });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const pickEntry = await prisma.pickEntry.findUnique({
    where: { id: req.params.pickEntryId },
    include: {
      coilItem: {
        include: {
          coil: {
            include: { machine: true },
          },
        },
      },
    },
  });

  if (!pickEntry || pickEntry.runId !== run.id || pickEntry.coilItem.coil.machine.companyId !== req.auth.companyId) {
    return res.status(404).json({ error: 'Pick entry not found' });
  }

  await prisma.pickEntry.delete({ where: { id: pickEntry.id } });
  return res.status(204).send();
});

router.get('/:runId/chocolate-boxes', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  return res.json(run.chocolateBoxes);
});

router.post('/:runId/chocolate-boxes', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to create chocolate boxes' });
  }

  const parsed = createChocolateBoxSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const machine = await ensureMachine(req.auth.companyId, parsed.data.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found for this company' });
  }

  try {
    const chocolateBox = await prisma.chocolateBox.create({
      data: {
        runId: run.id,
        machineId: machine.id,
        number: parsed.data.number,
      },
      include: { machine: true },
    });
    return res.status(201).json(chocolateBox);
  } catch (error) {
    return res.status(409).json({ error: 'Chocolate box number already exists for this run', detail: (error as Error).message });
  }
});

router.patch('/:runId/chocolate-boxes/:chocolateBoxId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update chocolate boxes' });
  }

  const parsed = updateChocolateBoxSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const chocolateBox = await prisma.chocolateBox.findUnique({
    where: { id: req.params.chocolateBoxId },
    include: { machine: true },
  });

  if (!chocolateBox || chocolateBox.runId !== run.id || chocolateBox.machine.companyId !== req.auth.companyId) {
    return res.status(404).json({ error: 'Chocolate box not found' });
  }

  if (parsed.data.machineId) {
    const machine = await ensureMachine(req.auth.companyId, parsed.data.machineId);
    if (!machine) {
      return res.status(404).json({ error: 'Machine not found for this company' });
    }
  }

  const data: { machineId?: string; number?: number } = {};
  if (parsed.data.machineId !== undefined) {
    data.machineId = parsed.data.machineId;
  }
  if (parsed.data.number !== undefined) {
    data.number = parsed.data.number;
  }

  try {
    const updated = await prisma.chocolateBox.update({
      where: { id: chocolateBox.id },
      data,
      include: { machine: true },
    });
    return res.json(updated);
  } catch (error) {
    return res.status(409).json({ error: 'Chocolate box number already exists for this run', detail: (error as Error).message });
  }
});

router.delete('/:runId/chocolate-boxes/:chocolateBoxId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete chocolate boxes' });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const chocolateBox = await prisma.chocolateBox.findUnique({
    where: { id: req.params.chocolateBoxId },
    include: { machine: true },
  });

  if (!chocolateBox || chocolateBox.runId !== run.id || chocolateBox.machine.companyId !== req.auth.companyId) {
    return res.status(404).json({ error: 'Chocolate box not found' });
  }

  await prisma.chocolateBox.delete({ where: { id: chocolateBox.id } });
  return res.status(204).send();
});

export const runsRouter = router;
