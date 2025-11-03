import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { RunItemStatus, isRunStatus } from '../types/enums.js';
import type { RunStatus as RunStatusValue, RunItemStatus as RunItemStatusValue } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { isCompanyManager } from './helpers/authorization.js';
import {
  createRunSchema,
  updateRunSchema,
  createPickEntrySchema,
  updatePickEntrySchema,
  createChocolateBoxSchema,
  updateChocolateBoxSchema,
  runAssignmentSchema,
  ensureMembership,
  ensureRun,
  ensureCoilItem,
  ensureMachine,
} from './helpers/runs.js';

const router = Router();

router.use(authenticate);

// Lists runs for the current company, optionally filtered by status.
router.get('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { status } = req.query;
  const where: Prisma.RunWhereInput = { companyId: req.auth.companyId };
  if (isRunStatus(status)) {
    where.status = { equals: status as Prisma.$Enums.RunStatus };
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

// Provides aggregated run information from the overview reporting view.
router.get('/overview', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type VRunOverviewRow = {
    run_id: string;
    company_id: string;
    company_name: string;
    run_status: RunStatusValue;
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

// Returns upcoming runs that still need to be picked.
router.get('/tobepicked', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type VRunOverviewRow = {
    run_id: string;
    company_id: string;
    company_name: string;
    run_status: RunStatusValue;
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

// Exposes pick entry data for reporting with optional run filtering.
router.get('/pick-entries', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  type VRunPickEntriesRow = {
    pick_entry_id: string;
    run_id: string;
    coil_item_id: string;
    picked_count: number;
    pick_status: RunItemStatusValue;
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

// Fetches chocolate box details from the reporting view.
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
    run_status: RunStatusValue;
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

// Creates a new run and optionally links picker and runner memberships.
router.post('/', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
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
      status: Prisma.$Enums.RunStatus.CREATED, // Always start new runs as CREATED
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

// Loads a single run with its pick entries and chocolate boxes.
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

// Updates run metadata such as scheduled dates and status.
router.patch('/:runId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
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

  const data: Prisma.RunUncheckedUpdateInput = {};

  if (parsed.data.pickerId !== undefined) {
    data.pickerId = parsed.data.pickerId ?? null;
  }
  if (parsed.data.runnerId !== undefined) {
    data.runnerId = parsed.data.runnerId ?? null;
  }
  if (parsed.data.status !== undefined) {
    data.status = parsed.data.status as Prisma.$Enums.RunStatus;
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

// Assigns or unassigns a picker or runner to a run.
router.post('/:runId/assignment', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
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

// Deletes a run and all related records.
router.delete('/:runId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete runs' });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  await prisma.run.delete({ where: { id: run.id } });
  return res.status(204).send();
});

// Returns pick entries linked to a specific run.
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

// Adds a pick entry to a run.
router.post('/:runId/pick-entries', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
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
        status: (parsed.data.status ?? RunItemStatus.PENDING) as Prisma.$Enums.RunItemStatus,
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

// Updates an existing pick entry for the run.
router.patch('/:runId/pick-entries/:pickEntryId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
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

  const data: Prisma.PickEntryUncheckedUpdateInput = {};

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
    data.status = parsed.data.status as Prisma.$Enums.RunItemStatus;
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

// Removes a pick entry from the run.
router.delete('/:runId/pick-entries/:pickEntryId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
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

// Lists chocolate boxes associated with a run.
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

// Adds a chocolate box assignment to a run.
router.post('/:runId/chocolate-boxes', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
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

// Updates an existing chocolate box assignment.
router.patch('/:runId/chocolate-boxes/:chocolateBoxId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
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

// Removes a chocolate box from the run.
router.delete('/:runId/chocolate-boxes/:chocolateBoxId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
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
