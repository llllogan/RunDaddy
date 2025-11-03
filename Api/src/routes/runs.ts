import { Buffer } from 'node:buffer';
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

const trimNullTerminators = (value: string): string => value.replace(/\0+$/, '');
const isPrintableAscii = (value: string): boolean => /^[\x20-\x7E\r\n\t]+$/.test(value);

const formatHexId = (hex: string): string => {
  if (hex.length === 32) {
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }
  return hex;
};

const decodeBufferLike = (buffer: Uint8Array): string | null => {
  if (!buffer.length) {
    return null;
  }

  const utf8 = trimNullTerminators(Buffer.from(buffer).toString('utf8')).trim();
  if (utf8 && isPrintableAscii(utf8)) {
    return utf8;
  }

  const hex = Buffer.from(buffer).toString('hex');
  return hex ? formatHexId(hex) : null;
};

const normalizeStoredText = (value: unknown): string | null => {
  if (value === null || value === undefined) {
    return null;
  }

  if (typeof value === 'string' || value instanceof String) {
    const trimmed = trimNullTerminators(String(value)).trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }

  if (value instanceof Uint8Array) {
    return decodeBufferLike(value);
  }

  if (ArrayBuffer.isView(value)) {
    const view = value as ArrayBufferView;
    return decodeBufferLike(new Uint8Array(view.buffer, view.byteOffset, view.byteLength));
  }

  if (value instanceof ArrayBuffer) {
    return decodeBufferLike(new Uint8Array(value));
  }

  if (typeof value === 'object' && value) {
    const candidate = value as { type?: unknown; data?: unknown };
    if (candidate.type === 'Buffer' && Array.isArray(candidate.data)) {
      return decodeBufferLike(Uint8Array.from(candidate.data as number[]));
    }
    if ('toString' in candidate) {
      const stringified = trimNullTerminators(String(candidate)).trim();
      return stringified.length > 0 && stringified !== '[object Object]' ? stringified : null;
    }
  }

  return null;
};

const normalizeStoredId = (value: unknown): string | null => {
  const normalized = normalizeStoredText(value);
  if (normalized) {
    return normalized;
  }

  if (value === null || value === undefined) {
    return null;
  }

  const fallback = String(value).trim();
  if (fallback && fallback !== '[object Object]') {
    return fallback;
  }

  return null;
};

const valueFromRow = (row: unknown, column: string, index: number): unknown => {
  if (!row || typeof row !== 'object') {
    return undefined;
  }

  const record = row as Record<string, unknown>;
  if (column in record) {
    return record[column];
  }

  const fallbackKey = `f${index}`;
  if (fallbackKey in record) {
    return record[fallbackKey];
  }

  return undefined;
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

const runAssignmentSchema = z.object({
  userId: z.string().cuid(),
  role: z.enum(['PICKER', 'RUNNER']),
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
                  machine: {
                    include: {
                      location: true,
                    },
                  },
                },
              },
            },
          },
        },
      },
      chocolateBoxes: {
        include: {
          machine: {
            include: {
              location: true,
            },
          },
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

  type VRunOverviewRow = {
    run_id: string;
    company_id: string;
    company_name: string;
    run_status: RunStatus;
    scheduled_for: Date | null;
    picking_started_at: Date | null;
    picking_ended_at: Date | null;
    run_created_at: Date;
    picker_id: string | null;
    picker_first_name: string | null;
    picker_last_name: string | null;
    runner_id: string | null;
    runner_first_name: string | null;
    runner_last_name: string | null;
  };

  const { status } = req.query;
  const statusFilter = isRunStatus(status) ? status : null;

  const rows = await prisma.$queryRaw<VRunOverviewRow[]>(
    Prisma.sql`SELECT * FROM v_run_overview WHERE company_id = ${req.auth.companyId} ${statusFilter ? Prisma.sql`AND run_status = ${statusFilter}` : Prisma.empty} ORDER BY scheduled_for DESC, run_created_at DESC`,
  );

  return res.json(
    rows.map((row) => ({
      id: row.run_id,
      companyId: row.company_id,
      companyName: row.company_name,
      status: row.run_status,
      scheduledFor: row.scheduled_for,
      pickingStartedAt: row.picking_started_at,
      pickingEndedAt: row.picking_ended_at,
      createdAt: row.run_created_at,
      pickerId: row.picker_id,
      pickerFirstName: row.picker_first_name,
      pickerLastName: row.picker_last_name,
      runnerId: row.runner_id,
      runnerFirstName: row.runner_first_name,
      runnerLastName: row.runner_last_name,
    })),
  );
});

router.get('/tobepicked', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type VRunOverviewRow = {
    run_id: string;
    company_id: string;
    company_name: string;
    run_status: RunStatus;
    scheduled_for: Date | null;
    picking_started_at: Date | null;
    picking_ended_at: Date | null;
    run_created_at: Date;
    picker_id: string | null;
    picker_first_name: string | null;
    picker_last_name: string | null;
    runner_id: string | null;
    runner_first_name: string | null;
    runner_last_name: string | null;
  };

  const now = new Date();

  const rows = await prisma.$queryRaw<VRunOverviewRow[]>(
    Prisma.sql`SELECT * FROM v_run_overview WHERE company_id = ${req.auth.companyId} AND run_status IN ('CREATED', 'PICKING') AND scheduled_for >= ${now} ORDER BY scheduled_for ASC`,
  );

  return res.json(
    rows.map((row) => ({
      id: row.run_id,
      companyId: row.company_id,
      companyName: row.company_name,
      status: row.run_status,
      scheduledFor: row.scheduled_for,
      pickingStartedAt: row.picking_started_at,
      pickingEndedAt: row.picking_ended_at,
      createdAt: row.run_created_at,
      pickerId: row.picker_id,
      pickerFirstName: row.picker_first_name,
      pickerLastName: row.picker_last_name,
      runnerId: row.runner_id,
      runnerFirstName: row.runner_first_name,
      runnerLastName: row.runner_last_name,
    })),
  );
});

router.get('/pick-entries', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type VRunPickEntriesRow = {
    pick_entry_id: string;
    run_id: string;
    coil_item_id: string;
    picked_count: number;
    pick_status: RunItemStatus;
    picked_at: Date | null;
    company_id: string;
    company_name: string;
    coil_id: string;
    machine_id: string;
    machine_code: string;
    sku_id: string | null;
    sku_code: string | null;
    sku_name: string | null;
  };

  const { runId } = req.query;

  const runIdParam = typeof runId === 'string' ? runId : null;
  const rows = await prisma.$queryRaw<VRunPickEntriesRow[]>(
    Prisma.sql`SELECT * FROM v_run_pick_entries WHERE company_id = ${req.auth.companyId} ${runIdParam ? Prisma.sql`AND run_id = ${runIdParam}` : Prisma.empty} ORDER BY run_id DESC, pick_entry_id ASC`,
  );

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

  type VChocolateBoxDetailsRow = {
    chocolate_box_id: string;
    chocolate_box_number: number;
    run_id: string;
    machine_id: string;
    machine_code: string;
    company_id: string;
    company_name: string;
    run_status: RunStatus;
    scheduled_for: Date | null;
  };

  const { runId } = req.query;

  const runIdParam = typeof runId === 'string' ? runId : null;
  const rows = await prisma.$queryRaw<VChocolateBoxDetailsRow[]>(
    Prisma.sql`SELECT * FROM v_chocolate_box_details WHERE company_id = ${req.auth.companyId} ${runIdParam ? Prisma.sql`AND run_id = ${runIdParam}` : Prisma.empty} ORDER BY run_id DESC, chocolate_box_number ASC`,
  );

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
      status: RunStatus.CREATED, // Always start new runs as CREATED
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

router.post('/:runId/assignment', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!canManage(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to assign runs' });
  }

  const parsed = runAssignmentSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const membership = await ensureMembership(req.auth.companyId, parsed.data.userId);
  if (!membership) {
    return res.status(404).json({ error: 'User not found in company' });
  }

  const updateData = parsed.data.role === 'PICKER'
    ? { pickerId: parsed.data.userId }
    : { runnerId: parsed.data.userId };

  const updatedRun = await prisma.run.update({
    where: { id: run.id },
    data: updateData,
    include: {
      picker: true,
      runner: true,
    },
  });

  return res.status(200).json({
    id: updatedRun.id,
    companyId: updatedRun.companyId,
    status: updatedRun.status,
    scheduledFor: updatedRun.scheduledFor,
    pickingStartedAt: updatedRun.pickingStartedAt,
    pickingEndedAt: updatedRun.pickingEndedAt,
    createdAt: updatedRun.createdAt,
    picker: updatedRun.picker
      ? {
          id: updatedRun.picker.id,
          firstName: updatedRun.picker.firstName,
          lastName: updatedRun.picker.lastName,
        }
      : null,
    runner: updatedRun.runner
      ? {
          id: updatedRun.runner.id,
          firstName: updatedRun.runner.firstName,
          lastName: updatedRun.runner.lastName,
        }
      : null,
  });
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
