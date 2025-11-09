import type { Request, Response } from 'express';
import multer from 'multer';
import { Prisma } from '@prisma/client';
import type { RunStatus as PrismaRunStatus } from '@prisma/client';
import { parseRunWorkbook } from '../../lib/run-import-parser.js';
import { prisma } from '../../lib/prisma.js';
import { RunStatus as AppRunStatus } from '../../types/enums.js';
import type {
  ParsedCoilItem,
  ParsedMachine,
  ParsedMachineLocation,
  ParsedMachineType,
  ParsedPickEntry,
  ParsedRun,
} from '../../types/run-import.js';

export class RunImportError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RunImportError';
  }
}

const TIMEZONE_FORMAT_OPTIONS: Intl.DateTimeFormatOptions = {
  hour12: false,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
};

export const isValidTimezone = (value: string): boolean => {
  try {
    new Intl.DateTimeFormat('en-US', { ...TIMEZONE_FORMAT_OPTIONS, timeZone: value }).format(new Date());
    return true;
  } catch {
    return false;
  }
};

const convertRunDateToTimezoneMidnight = (runDate: Date, timeZone: string): Date => {
  const baseDate = new Date(
    Date.UTC(runDate.getUTCFullYear(), runDate.getUTCMonth(), runDate.getUTCDate(), 0, 0, 0, 0),
  );

  const formatter = new Intl.DateTimeFormat('en-US', {
    ...TIMEZONE_FORMAT_OPTIONS,
    timeZone,
  });

  const parts = formatter.formatToParts(baseDate);
  const getPartValue = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? null;

  const year = Number.parseInt(getPartValue('year') ?? '', 10);
  const month = Number.parseInt(getPartValue('month') ?? '', 10) - 1;
  const day = Number.parseInt(getPartValue('day') ?? '', 10);
  const hour = Number.parseInt(getPartValue('hour') ?? '0', 10);
  const minute = Number.parseInt(getPartValue('minute') ?? '0', 10);
  const second = Number.parseInt(getPartValue('second') ?? '0', 10);

  if ([year, month, day, hour, minute, second].some((value) => !Number.isFinite(value))) {
    return runDate;
  }

  const asUtc = Date.UTC(year, month, day, hour, minute, second);
  const offset = asUtc - baseDate.getTime();
  return new Date(baseDate.getTime() - offset);
};

const determineScheduledFor = (runDate: Date | null, timeZone?: string): Date => {
  if (!runDate) {
    return new Date();
  }
  if (!timeZone) {
    return runDate;
  }
  return convertRunDateToTimezoneMidnight(runDate, timeZone);
};

export const runImportUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB
  },
});

export const uploadRunWorkbook = async (req: Request, res: Response) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.file) {
    return res.status(400).json({ error: 'Missing Excel file payload' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to import runs' });
  }

  const timezoneRaw =
    req.body && typeof req.body.timezone === 'string' ? req.body.timezone.trim() : undefined;
  if (timezoneRaw && !isValidTimezone(timezoneRaw)) {
    return res.status(400).json({
      error: 'Invalid timezone supplied. Please use an IANA timezone like "America/Chicago".',
    });
  }

  try {
    const workbook = await parseRunWorkbook(req.file.buffer);
    const run = workbook.run;

    if (!run || !run.pickEntries.length) {
      return res.status(400).json({
        error: 'Workbook did not contain any pick entries to import.',
      });
    }

    const createdRun = await persistRunFromWorkbook({
      run,
      companyId: req.auth.companyId,
      timezone: timezoneRaw,
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

type TransactionClient = Prisma.TransactionClient;

export const persistRunFromWorkbook = async ({
  run,
  companyId,
  timezone,
}: {
  run: ParsedRun;
  companyId: string;
  timezone?: string;
}) => {
  const scheduledFor = determineScheduledFor(run.runDate, timezone);

  return prisma.$transaction(
    async (tx) => {
      const helpers = createImportHelpers(tx, companyId);
      const runRecord = await tx.run.create({
        data: {
          companyId,
          status: AppRunStatus.CREATED as unknown as PrismaRunStatus,
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

  const ensureSku = async (sku: ParsedCoilItem['sku']): Promise<{ id: string; countNeededPointer?: string | null }> => {
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
      const category = sku.category?.trim() || null;
      if (category && existing.category !== category) {
        updates.category = category;
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
        category: sku.category?.trim() || null,
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

  // Use the SKU's countNeededPointer to determine which field to use
  const countPointer = skuRecord.countNeededPointer || 'total';
  let countValue = 0;

  switch (countPointer.toLowerCase()) {
    case 'count':
      countValue = normalizeInteger(entry.count, 0);
      break;
    case 'need':
      countValue = normalizeInteger(entry.need, 0);
      break;
    case 'forecast':
      countValue = normalizeInteger(entry.forecast, 0);
      break;
    case 'total':
    default:
      // Default behavior: try count, then need, then forecast, then fallback to 0
      countValue =
        normalizeInteger(entry.count, undefined) ??
        normalizeInteger(entry.need, undefined) ??
        normalizeInteger(entry.forecast, undefined) ??
        0;
      break;
  }

  await tx.pickEntry.create({
    data: {
      runId,
      coilItemId: coilItemRecord.id,
      count: countValue,
      current: normalizeInteger(entry.current),
      par: normalizeInteger(entry.par),
      need: normalizeInteger(entry.need),
      forecast: normalizeInteger(entry.forecast),
      total: normalizeInteger(entry.total),
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
