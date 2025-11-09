import { Router } from 'express';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { parseRunWorkbook } from '../lib/run-import-parser.js';
import { prisma } from '../lib/prisma.js';
import { setLogConfig } from '../middleware/logging.js';
import { RunImportError, isValidTimezone, persistRunFromWorkbook } from './helpers/run-imports.js';

const router = Router();

router.get('/companies', setLogConfig({ level: 'minimal' }), async (_req, res) => {
  try {
    const companies = await prisma.company.findMany({
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        name: true,
        createdAt: true,
        updatedAt: true,
        _count: {
          select: {
            memberships: true,
            runs: true,
            locations: true,
            machines: true,
          },
        },
      },
    });

    return res.json({ companies });
  } catch (error) {
    console.error('Debug list companies failed', error);
    return res.status(500).json({
      error: 'Unable to list companies',
      detail: (error as Error).message,
    });
  }
});

router.get('/users', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const companyId = typeof req.query.companyId === 'string' ? req.query.companyId : undefined;

  try {
    const users = await prisma.user.findMany({
      ...(companyId
        ? {
            where: {
              memberships: {
                some: { companyId },
              },
            },
          }
        : {}),
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        role: true,
        phone: true,
        createdAt: true,
        updatedAt: true,
        defaultMembershipId: true,
        memberships: {
          select: {
            id: true,
            companyId: true,
            role: true,
          },
        },
      },
    });

    return res.json({ users, filter: { companyId } });
  } catch (error) {
    console.error('Debug list users failed', error);
    return res.status(500).json({
      error: 'Unable to list users',
      detail: (error as Error).message,
    });
  }
});

router.post('/run-imports', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const { companyId, workbookPath, excelPath } = req.body ?? {};
  const timezoneRaw =
    req.body && typeof req.body.timezone === 'string' ? req.body.timezone.trim() : undefined;

  if (!companyId || typeof companyId !== 'string') {
    return res.status(400).json({ error: 'companyId is required' });
  }

  const providedPath = typeof workbookPath === 'string' ? workbookPath : typeof excelPath === 'string' ? excelPath : null;

  if (!providedPath) {
    return res.status(400).json({ error: 'workbookPath (or excelPath) is required' });
  }

  if (timezoneRaw && !isValidTimezone(timezoneRaw)) {
    return res.status(400).json({
      error: 'Invalid timezone supplied. Please use an IANA timezone like "America/Chicago".',
    });
  }

  const resolvedPath = path.isAbsolute(providedPath) ? providedPath : path.resolve(process.cwd(), providedPath);

  let workbookBuffer: Buffer;
  try {
    workbookBuffer = await readFile(resolvedPath);
  } catch (error) {
    return res.status(400).json({
      error: `Unable to read workbook at path: ${resolvedPath}`,
      detail: (error as Error).message,
    });
  }

  try {
    const parsed = await parseRunWorkbook(workbookBuffer);
    const run = parsed.run;

    if (!run || !run.pickEntries.length) {
      return res.status(400).json({
        error: 'Workbook did not contain any pick entries to import.',
      });
    }

    const createdRun = await persistRunFromWorkbook({
      run,
      companyId,
      timezone: timezoneRaw,
    });

    const pickEntryCount = run.pickEntries.length;
    const machineCount = new Set(run.pickEntries.map((entry) => entry.coilItem.coil.machine.code)).size;

    return res.status(201).json({
      summary: {
        runs: 1,
        machines: machineCount,
        pickEntries: pickEntryCount,
      },
      run: {
        id: createdRun.id,
        status: createdRun.status,
        scheduledFor: createdRun.scheduledFor,
        createdAt: createdRun.createdAt,
      },
    });
  } catch (error) {
    console.error('Debug run import failed', error);

    if (error instanceof RunImportError) {
      return res.status(400).json({ error: error.message });
    }

    return res.status(500).json({
      error: 'Unable to import workbook',
      detail: (error as Error).message,
    });
  }
});

router.delete('/runs/:runId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const { runId } = req.params;
  const { companyId } = req.query;

  if (!runId || typeof runId !== 'string') {
    return res.status(400).json({ error: 'runId is required' });
  }

  if (!companyId || typeof companyId !== 'string') {
    return res.status(400).json({ error: 'companyId is required' });
  }

  try {
    // First verify the run exists and belongs to the company
    const run = await prisma.run.findUnique({
      where: { id: runId },
      include: {
        _count: {
          select: {
            pickEntries: true,
            chocolateBoxes: true,
          },
        },
      },
    });

    if (!run) {
      return res.status(404).json({ error: 'Run not found' });
    }

    if (run.companyId !== companyId) {
      return res.status(403).json({ error: 'Run does not belong to the specified company' });
    }

    // Delete the run (cascading deletes will handle pickEntries and chocolateBoxes)
    await prisma.run.delete({
      where: { id: runId },
    });

    return res.json({
      message: 'Run deleted successfully',
      deletedRun: {
        id: run.id,
        status: run.status,
        scheduledFor: run.scheduledFor,
        createdAt: run.createdAt,
        deletedCounts: run._count,
      },
    });
  } catch (error) {
    console.error('Debug delete run failed', error);
    return res.status(500).json({
      error: 'Unable to delete run',
      detail: (error as Error).message,
    });
  }
});

export const debugRouter = router;
