import { Router } from 'express';
import { Prisma } from '@prisma/client';
import type { RunStatus as PrismaRunStatus, RunItemStatus as PrismaRunItemStatus } from '@prisma/client';
import { RunItemStatus, RunStatus as AppRunStatus, isRunStatus } from '../types/enums.js';
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
    where.status = { equals: status as unknown as PrismaRunStatus };
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

// Get all runs scheduled for today
// Include the number of locations
router.get('/today', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);

  const runs = await fetchScheduledRuns(req.auth.companyId, startOfToday);

  return res.json(runs);
});

// Get all runs scheduled for tomorrow
router.get('/tomorrow', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  const startOfTomorrow = new Date();
  startOfTomorrow.setDate(startOfTomorrow.getDate() + 1);
  startOfTomorrow.setHours(0, 0, 0, 0);

  const runs = await fetchScheduledRuns(req.auth.companyId, startOfTomorrow);

  return res.json(runs);
});

// Get runs scheduled for tomorrow with a status of READY
router.get('/tomorrow/ready', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const startOfTomorrow = new Date();
  startOfTomorrow.setDate(startOfTomorrow.getDate() + 1);
  startOfTomorrow.setHours(0, 0, 0, 0);
  const endOfTomorrow = new Date();
  endOfTomorrow.setDate(endOfTomorrow.getDate() + 1);
  endOfTomorrow.setHours(23, 59, 59, 999);

  const runs = await prisma.run.findMany({
    where: {
      companyId: req.auth.companyId,
      scheduledFor: {
        gte: startOfTomorrow,
        lte: endOfTomorrow,
      },
      status: AppRunStatus.READY,
    },
    orderBy: { scheduledFor: 'asc' },
    include: {
      picker: true,
      runner: true,
    },
  });

  return res.json(runs);
});

router.get('/runs/:runId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { runId } = req.params;
  if (!runId) {
    return res.status(400).json({ error: 'Run ID is required' });
  }

  const payload = await getRunDetailPayload(req.auth.companyId, runId);
  if (!payload) {
    return res.status(404).json({ error: 'Run not found' });
  }

  return res.json(payload);
});

// Assigns or unassigns a picker or runner to a run.
router.post('/runs/:runId/assignment', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const runId = req.params.runId.trim();
  console.log('Assignment request: runId=', runId, 'companyId=', req.auth.companyId, 'userId=', req.auth.userId);

  const parsed = runAssignmentSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  console.log('Run found:', !!run, run?.companyId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const membership = await ensureMembership(req.auth.companyId, parsed.data.userId);
  if (!membership) {
    return res.status(404).json({ error: 'User not found in company' });
  }

  const isSelfAssignment = parsed.data.userId === req.auth.userId;
  const isManager = isCompanyManager(req.auth.role);

  if (!isManager && !isSelfAssignment) {
    return res.status(403).json({ error: 'Insufficient permissions to assign runs' });
  }

  // For self-assignment, check if the role is already taken
  if (isSelfAssignment && !isManager) {
    const isPickerTaken = parsed.data.role === 'PICKER' && run.pickerId != null && run.pickerId !== req.auth.userId;
    const isRunnerTaken = parsed.data.role === 'RUNNER' && run.runnerId != null && run.runnerId !== req.auth.userId;
    if (isPickerTaken || isRunnerTaken) {
      return res.status(409).json({ error: 'Role is already assigned to another user' });
    }
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
  });
});

// Deletes a run and all related records.
router.delete('/runs/:runId', async (req, res) => {
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

type RunDetailSource = NonNullable<Awaited<ReturnType<typeof ensureRun>>>;

type LocationPayload = {
  id: string;
  name: string | null;
  address: string | null;
};

type MachineTypePayload = {
  id: string;
  name: string;
  description: string | null;
} | null;

type MachinePayload = {
  id: string;
  code: string;
  description: string | null;
  machineType: MachineTypePayload;
  location: LocationPayload | null;
};

type PickItemPayload = {
  id: string;
  count: number;
  status: RunItemStatusValue;
  pickedAt: Date | null;
  coilItem: {
    id: string;
    par: number;
  };
  coil: {
    id: string;
    code: string;
    machineId: string | null;
  };
  sku: null | {
    id: string;
    code: string;
    name: string;
    type: string;
    isCheeseAndCrackers: boolean;
  };
  machine: MachinePayload | null;
  location: LocationPayload | null;
};

type RunDetailPayload = {
  id: string;
  status: PrismaRunStatus;
  companyId: string;
  scheduledFor: Date | null;
  pickingStartedAt: Date | null;
  pickingEndedAt: Date | null;
  createdAt: Date;
  picker: null | {
    id: string;
    firstName: string | null;
    lastName: string | null;
  };
  runner: null | {
    id: string;
    firstName: string | null;
    lastName: string | null;
  };
  locations: LocationPayload[];
  machines: MachinePayload[];
  pickItems: PickItemPayload[];
  pickEntries: Array<{
    id: string;
    count: number;
    status: RunItemStatusValue;
    pickedAt: Date | null;
    coilItem: {
      id: string;
      par: number;
      coil: {
        id: string;
        code: string;
        machine: MachinePayload | null;
      };
      sku: PickItemPayload['sku'];
    };
  }>;
  chocolateBoxes: Array<{
    id: string;
    number: number;
    machine: MachinePayload | null;
  }>;
};

function buildRunDetailPayload(run: RunDetailSource): RunDetailPayload {
  const machinesById = new Map<string, MachinePayload>();
  const locationsById = new Map<string, LocationPayload>();

  const serializeLocation = (
    location: RunDetailSource['pickEntries'][number]['coilItem']['coil']['machine']['location'],
  ): LocationPayload | null => {
    if (!location) {
      return null;
    }

    const existing = locationsById.get(location.id);
    if (existing) {
      return existing;
    }

    const serialized: LocationPayload = {
      id: location.id,
      name: location.name,
      address: location.address,
    };
    locationsById.set(location.id, serialized);
    return serialized;
  };

  const serializeMachine = (
    machine: RunDetailSource['pickEntries'][number]['coilItem']['coil']['machine'] | null | undefined,
  ): MachinePayload | null => {
    if (!machine) {
      return null;
    }

    const existing = machinesById.get(machine.id);
    if (existing) {
      return existing;
    }

    const serialized: MachinePayload = {
      id: machine.id,
      code: machine.code,
      description: machine.description,
      machineType: machine.machineType
        ? {
            id: machine.machineType.id,
            name: machine.machineType.name,
            description: machine.machineType.description,
          }
        : null,
      location: serializeLocation(machine.location),
    };

    machinesById.set(machine.id, serialized);
    return serialized;
  };

  const pickItems: PickItemPayload[] = run.pickEntries.map((entry) => {
    const machine = entry.coilItem.coil.machine;
    const serializedMachine = serializeMachine(machine);
    const serializedLocation = machine ? serializeLocation(machine.location) : null;

    return {
      id: entry.id,
      count: entry.count,
      status: entry.status as RunItemStatusValue,
      pickedAt: entry.pickedAt,
      coilItem: {
        id: entry.coilItem.id,
        par: entry.coilItem.par,
      },
      coil: {
        id: entry.coilItem.coil.id,
        code: entry.coilItem.coil.code,
        machineId: machine?.id ?? null,
      },
      sku: entry.coilItem.sku
        ? {
            id: entry.coilItem.sku.id,
            code: entry.coilItem.sku.code,
            name: entry.coilItem.sku.name,
            type: entry.coilItem.sku.type,
            isCheeseAndCrackers: entry.coilItem.sku.isCheeseAndCrackers,
          }
        : null,
      machine: serializedMachine,
      location: serializedLocation,
    };
  });

  const chocolateBoxes = run.chocolateBoxes.map((box) => ({
    id: box.id,
    number: box.number,
    machine: serializeMachine(box.machine),
  }));

  return {
    id: run.id,
    status: run.status,
    companyId: run.companyId,
    scheduledFor: run.scheduledFor,
    pickingStartedAt: run.pickingStartedAt,
    pickingEndedAt: run.pickingEndedAt,
    createdAt: run.createdAt,
    picker: run.picker
      ? {
          id: run.picker.id,
          firstName: run.picker.firstName,
          lastName: run.picker.lastName,
        }
      : null,
    runner: run.runner
      ? {
          id: run.runner.id,
          firstName: run.runner.firstName,
          lastName: run.runner.lastName,
        }
      : null,
    locations: Array.from(locationsById.values()),
    machines: Array.from(machinesById.values()),
    pickItems,
    pickEntries: run.pickEntries.map((entry) => ({
      id: entry.id,
      count: entry.count,
      status: entry.status as RunItemStatusValue,
      pickedAt: entry.pickedAt,
      coilItem: {
        id: entry.coilItem.id,
        par: entry.coilItem.par,
        coil: {
          id: entry.coilItem.coil.id,
          code: entry.coilItem.coil.code,
          machine: serializeMachine(entry.coilItem.coil.machine),
        },
        sku: entry.coilItem.sku
          ? {
              id: entry.coilItem.sku.id,
              code: entry.coilItem.sku.code,
              name: entry.coilItem.sku.name,
              type: entry.coilItem.sku.type,
              isCheeseAndCrackers: entry.coilItem.sku.isCheeseAndCrackers,
            }
          : null,
      },
    })),
    chocolateBoxes,
  };
}

export async function getRunDetailPayload(companyId: string, runId: string): Promise<RunDetailPayload | null> {
  const run = await ensureRun(companyId, runId);
  if (!run) {
    return null;
  }

  return buildRunDetailPayload(run);
}

type RunDailyLocationRow = {
  run_id: string;
  company_id: string;
  company_name: string;
  scheduled_date: Date | string | null;
  scheduled_for: Date | null;
  run_status: PrismaRunStatus;
  picking_started_at: Date | null;
  picking_ended_at: Date | null;
  run_created_at: Date;
  picker_id: string | null;
  picker_first_name: string | null;
  picker_last_name: string | null;
  runner_id: string | null;
  runner_first_name: string | null;
  runner_last_name: string | null;
  location_count: bigint | number | string | null;
};

type RunDailyResponse = {
  id: string;
  companyId: string;
  status: PrismaRunStatus;
  scheduledFor: Date | null;
  pickingStartedAt: Date | null;
  pickingEndedAt: Date | null;
  createdAt: Date;
  pickerId: string | null;
  runnerId: string | null;
  locationCount: number;
  picker: null | {
    id: string;
    firstName: string | null;
    lastName: string | null;
  };
  runner: null | {
    id: string;
    firstName: string | null;
    lastName: string | null;
  };
};

async function fetchScheduledRuns(companyId: string, scheduledDate: Date): Promise<RunDailyResponse[]> {
  const formattedDate = formatDateYmd(scheduledDate);

  const rows = await prisma.$queryRaw<RunDailyLocationRow[]>(
    Prisma.sql`
      SELECT
        run_id,
        company_id,
        company_name,
        scheduled_date,
        scheduled_for,
        run_status,
        picking_started_at,
        picking_ended_at,
        run_created_at,
        picker_id,
        picker_first_name,
        picker_last_name,
        runner_id,
        runner_first_name,
        runner_last_name,
        location_count
      FROM v_run_daily_locations
      WHERE company_id = ${companyId}
        AND scheduled_date = ${formattedDate}
      ORDER BY scheduled_for ASC, run_created_at ASC
    `,
  );

  return rows.map((row) => ({
    id: row.run_id,
    companyId: row.company_id,
    status: row.run_status,
    scheduledFor: row.scheduled_for,
    pickingStartedAt: row.picking_started_at,
    pickingEndedAt: row.picking_ended_at,
    createdAt: row.run_created_at,
    pickerId: row.picker_id,
    runnerId: row.runner_id,
    locationCount: Number(row.location_count ?? 0),
    picker: buildParticipant(row.picker_id, row.picker_first_name, row.picker_last_name),
    runner: buildParticipant(row.runner_id, row.runner_first_name, row.runner_last_name),
  }));
}

function buildParticipant(
  id: string | null,
  firstName: string | null,
  lastName: string | null,
): RunDailyResponse['picker'] {
  if (!id) {
    return null;
  }

  return {
    id,
    firstName,
    lastName,
  };
}

function formatDateYmd(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export const runRouter = router;
