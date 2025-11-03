import type { Request, Response } from 'express';
import { Router } from 'express';
import multer from 'multer';
import { parseRunWorkbook } from '../lib/run-import-parser.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import type {
  ParsedCoilItem,
  ParsedMachine,
  ParsedMachineLocation,
  ParsedMachineType,
  ParsedPickEntry,
  ParsedRun,
} from '../types/run-import.js';
import { Prisma } from '@prisma/client';
import { RunStatus } from '../types/enums.js';

class RunImportError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RunImportError';
  }
}

const router = Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB
  },
});

router.use(authenticate);

const uploadRunWorkbook = async (req: Request, res: Response) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.file) {
    return res.status(400).json({ error: 'Missing Excel file payload' });
  }

  try {
    const workbook = parseRunWorkbook(req.file.buffer);
    const run = workbook.run;

    if (!run || !run.pickEntries.length) {
      return res.status(400).json({
        error: 'Workbook did not contain any pick entries to import.',
      });
    }

    const createdRun = await persistRunFromWorkbook({
      run,
      companyId: req.auth.companyId,
    });

    const pickEntryCount = run.pickEntries.length;
    const machineCount = new Set(run.pickEntries.map((entry) => entry.coilItem.coil.machine.code)).size;

    return res.status(201).json({
      summary: {
        runs: run ? 1 : 0,
        machines: machineCount,
        pickEntries: pickEntryCount,
      },
      workbook,
      run: {
        id: createdRun.id,
        status: createdRun.status,
        scheduledFor: createdRun.scheduledFor,
        createdAt: createdRun.createdAt,
      },
    });
  } catch (error) {
    console.error('Failed to import run workbook', error);
    if (error instanceof RunImportError) {
      return res.status(400).json({
        error: error.message,
      });
    }
    return res.status(500).json({
      error: 'Unable to import workbook',
      detail: (error as Error).message,
    });
  }
};

router.post('/runs', upload.single('file'), uploadRunWorkbook);

export const runImportsRouter = router;

type TransactionClient = Prisma.TransactionClient;

const persistRunFromWorkbook = async ({ run, companyId }: { run: ParsedRun; companyId: string }) => {
  const scheduledFor = run.runDate ?? new Date();

  return prisma.$transaction(
    async (tx) => {
      const helpers = createImportHelpers(tx, companyId);
      const runRecord = await tx.run.create({
        data: {
          companyId,
          status: RunStatus.CREATED,
          scheduledFor,
        },
      });

      for (const entry of run.pickEntries) {
        await persistPickEntry(tx, helpers, runRecord.id, entry);
      }

      return runRecord;
    },
    {
      timeout: 200000,
      maxWait: 5000,
    },
  );
};

const createImportHelpers = (tx: TransactionClient, companyId: string) => {
  const locationCache = new Map<string, { id: string } | null>();
  const machineTypeCache = new Map<string, { id: string }>();
  const machineCache = new Map<string, { id: string }>();
  const skuCache = new Map<string, { id: string }>();
  const coilCache = new Map<string, { id: string }>();
  const coilItemCache = new Map<string, { id: string }>();

  const ensureLocation = async (location: ParsedMachineLocation | null): Promise<{ id: string } | null> => {
    if (!location || !location.name.trim()) {
      return null;
    }
    const key = location.name.trim().toLowerCase();
    if (locationCache.has(key)) {
      return locationCache.get(key) ?? null;
    }
    const existing = await tx.location.findFirst({
      where: {
        companyId,
        name: location.name.trim(),
      },
    });
    if (existing) {
      if (location.address && existing.address !== location.address) {
        await tx.location.update({
          where: { id: existing.id },
          data: { address: location.address },
        });
      }
      locationCache.set(key, existing);
      return existing;
    }
    const created = await tx.location.create({
      data: {
        companyId,
        name: location.name.trim(),
        address: location.address ?? null,
      },
    });
    locationCache.set(key, created);
    return created;
  };

  const ensureMachineType = async (machineType: ParsedMachineType | null): Promise<{ id: string }> => {
    const fallbackName = 'General';
    const name = machineType?.name?.trim() || fallbackName;
    const key = name.toLowerCase();
    if (machineTypeCache.has(key)) {
      return machineTypeCache.get(key)!;
    }
    const existing = await tx.machineType.findUnique({
      where: { name },
    });
    if (existing) {
      if (machineType?.category && existing.description !== machineType.category) {
        await tx.machineType.update({
          where: { id: existing.id },
          data: { description: machineType.category },
        });
      }
      machineTypeCache.set(key, existing);
      return existing;
    }
    const created = await tx.machineType.create({
      data: {
        name,
        description: machineType?.category ?? null,
      },
    });
    machineTypeCache.set(key, created);
    return created;
  };

  const ensureMachine = async (
    machine: ParsedMachine,
    machineTypeId: string,
    location: { id: string } | null,
  ): Promise<{ id: string }> => {
    const code = machine.code?.trim();
    if (!code) {
      throw new RunImportError('Encountered a machine without a code in the workbook.');
    }
    const key = `${code.toLowerCase()}`;
    if (machineCache.has(key)) {
      return machineCache.get(key)!;
    }
    const existing = await tx.machine.findFirst({
      where: {
        companyId,
        code,
      },
    });
    if (existing) {
      const updates: Prisma.MachineUncheckedUpdateInput = {};
      if (location && existing.locationId !== location.id) {
        updates.locationId = location.id;
      }
      if (existing.machineTypeId !== machineTypeId) {
        updates.machineTypeId = machineTypeId;
      }
      const description = machine.name?.trim() || null;
      if (description && existing.description !== description) {
        updates.description = description;
      }
      if (Object.keys(updates).length) {
        const updated = await tx.machine.update({
          where: { id: existing.id },
          data: updates,
        });
        machineCache.set(key, updated);
        return updated;
      }
      machineCache.set(key, existing);
      return existing;
    }
    const machineData: Prisma.MachineUncheckedCreateInput = {
      companyId,
      code,
      description: machine.name?.trim() || null,
      machineTypeId,
      locationId: location?.id ?? null,
    };
    const created = await tx.machine.create({
      data: machineData,
    });
    machineCache.set(key, created);
    return created;
  };

  const ensureCoil = async (machineId: string, code: string): Promise<{ id: string }> => {
    const normalizedCode = code?.trim();
    if (!normalizedCode) {
      throw new RunImportError('Encountered a coil without a code in the workbook.');
    }
    const key = `${machineId}:${normalizedCode.toLowerCase()}`;
    if (coilCache.has(key)) {
      return coilCache.get(key)!;
    }
    const existing = await tx.coil.findFirst({
      where: {
        machineId,
        code: normalizedCode,
      },
    });
    if (existing) {
      coilCache.set(key, existing);
      return existing;
    }
    const created = await tx.coil.create({
      data: {
        machineId,
        code: normalizedCode,
      },
    });
    coilCache.set(key, created);
    return created;
  };

  const ensureSku = async (sku: ParsedCoilItem['sku']): Promise<{ id: string }> => {
    const code = sku.code?.trim();
    if (!code) {
      throw new RunImportError('Encountered a SKU without a code in the workbook.');
    }
    const key = code.toLowerCase();
    if (skuCache.has(key)) {
      return skuCache.get(key)!;
    }
    const existing = await tx.sKU.findUnique({
      where: { code },
    });
    if (existing) {
      const updates: Prisma.SKUUpdateInput = {};
      const name = sku.name?.trim() || null;
      if (name && existing.name !== name) {
        updates.name = name;
      }
      const type = sku.type?.trim() || 'General';
      if (type && existing.type !== type) {
        updates.type = type;
      }
      if (Object.keys(updates).length) {
        const updated = await tx.sKU.update({
          where: { id: existing.id },
          data: updates,
        });
        skuCache.set(key, updated);
        return updated;
      }
      skuCache.set(key, existing);
      return existing;
    }
    const created = await tx.sKU.create({
      data: {
        code,
        name: sku.name?.trim() || code,
        type: sku.type?.trim() || 'General',
      },
    });
    skuCache.set(key, created);
    return created;
  };

  const ensureCoilItem = async (
    coilId: string,
    skuId: string,
    pickEntry: ParsedPickEntry,
  ): Promise<{ id: string }> => {
    const key = `${coilId}:${skuId}`;
    if (coilItemCache.has(key)) {
      return coilItemCache.get(key)!;
    }
    const existing = await tx.coilItem.findUnique({
      where: {
        coilId_skuId: {
          coilId,
          skuId,
        },
      },
    });
    const parValue = normalizeInteger(pickEntry.par, 0);
    if (existing) {
      if (existing.par !== parValue) {
        const updated = await tx.coilItem.update({
          where: { id: existing.id },
          data: {
            par: parValue,
          },
        });
        coilItemCache.set(key, updated);
        return updated;
      }
      coilItemCache.set(key, existing);
      return existing;
    }
    const created = await tx.coilItem.create({
      data: {
        coilId,
        skuId,
        par: parValue,
      },
    });
    coilItemCache.set(key, created);
    return created;
  };

  return {
    ensureLocation,
    ensureMachineType,
    ensureMachine,
    ensureCoil,
    ensureSku,
    ensureCoilItem,
  };
};

const persistPickEntry = async (
  tx: TransactionClient,
  helpers: ReturnType<typeof createImportHelpers>,
  runId: string,
  entry: ParsedPickEntry,
) => {
  const machine = entry.coilItem.coil.machine;

  const locationRecord = await helpers.ensureLocation(machine.location);
  const machineTypeRecord = await helpers.ensureMachineType(machine.machineType);
  const machineRecord = await helpers.ensureMachine(machine, machineTypeRecord.id, locationRecord);
  const coilRecord = await helpers.ensureCoil(machineRecord.id, entry.coilItem.coil.code);
  const skuRecord = await helpers.ensureSku(entry.coilItem.sku);
  const coilItemRecord = await helpers.ensureCoilItem(coilRecord.id, skuRecord.id, entry);

  const countValue =
    normalizeInteger(entry.count) ??
    normalizeInteger(entry.need) ??
    normalizeInteger(entry.forecast) ??
    0;

  await tx.pickEntry.create({
    data: {
      runId,
      coilItemId: coilItemRecord.id,
      count: countValue,
    },
  });
};

function normalizeInteger(value: number | null | undefined, fallback: number): number;
function normalizeInteger(value: number | null | undefined, fallback?: number): number | null;
function normalizeInteger(value: number | null | undefined, fallback?: number): number | null {
  if (value === null || value === undefined) {
    return fallback ?? null;
  }
  if (!Number.isFinite(value)) {
    return fallback ?? null;
  }
  const rounded = Math.round(value);
  return Number.isFinite(rounded) ? rounded : fallback ?? null;
}
