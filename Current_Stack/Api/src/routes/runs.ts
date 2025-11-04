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
