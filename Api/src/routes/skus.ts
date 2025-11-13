import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { isCompanyManager } from './helpers/authorization.js';
import {
    getTimezoneDayRange,
    isValidTimezone,
    formatDateInTimezone,
    convertDateToTimezoneMidnight,
    getLocalDateParts,
    getWeekdayIndexInTimezone,
} from '../lib/timezone.js';
import { parseTimezoneQueryParam, resolveCompanyTimezone } from './helpers/timezone.js';

const router = Router();

router.use(authenticate);

// Update SKU isCheeseAndCrackers field
router.patch('/:skuId/cheese-and-crackers', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  const { isCheeseAndCrackers } = req.body;
  if (typeof isCheeseAndCrackers !== 'boolean') {
    return res.status(400).json({ error: 'isCheeseAndCrackers must be a boolean' });
  }

  // Find the SKU to ensure it exists and get company info
  const sku = await prisma.sKU.findFirst({
    where: {
      id: skuId,
    },
    include: {
      coilItems: {
        include: {
          coil: {
            include: {
              machine: {
                include: {
                  company: true,
                },
              },
            },
          },
        },
      },
    },
  });

  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }

  // Check if the SKU belongs to the user's company through any coil item
  const belongsToCompany = sku.coilItems.some(coilItem => 
    coilItem.coil.machine?.companyId === req.auth!.companyId
  );

  if (!belongsToCompany) {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  // Only managers can update SKU fields
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKU' });
  }

  const updatedSku = await prisma.sKU.update({
    where: { id: skuId },
    data: { isCheeseAndCrackers },
  });

  return res.json({
    id: updatedSku.id,
    code: updatedSku.code,
    name: updatedSku.name,
    type: updatedSku.type,
    isCheeseAndCrackers: updatedSku.isCheeseAndCrackers,
  });
});

// Update SKU countNeededPointer field
router.patch('/:skuId/count-pointer', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  const { countNeededPointer } = req.body;
  if (!countNeededPointer || typeof countNeededPointer !== 'string') {
    return res.status(400).json({ error: 'countNeededPointer must be a string' });
  }

  const validPointers = ['current', 'par', 'need', 'forecast', 'total'];
  if (!validPointers.includes(countNeededPointer.toLowerCase())) {
    return res.status(400).json({ error: 'countNeededPointer must be one of: current, par, need, forecast, total' });
  }

  // Find the SKU to ensure it exists and get company info
  const sku = await prisma.sKU.findFirst({
    where: {
      id: skuId,
    },
    include: {
      coilItems: {
        include: {
          coil: {
            include: {
              machine: {
                include: {
                  company: true,
                },
              },
            },
          },
        },
      },
    },
  });

  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }

  // Check if the SKU belongs to the user's company through any coil item
  const belongsToCompany = sku.coilItems.some(coilItem => 
    coilItem.coil.machine?.companyId === req.auth!.companyId
  );

  if (!belongsToCompany) {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  // Only managers can update SKU fields
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKU' });
  }

  const updatedSku = await prisma.sKU.update({
    where: { id: skuId },
    data: { countNeededPointer: countNeededPointer.toLowerCase() },
  });

  return res.json({
    id: updatedSku.id,
    code: updatedSku.code,
    name: updatedSku.name,
    type: updatedSku.type,
    countNeededPointer: updatedSku.countNeededPointer,
  });
});

// Get individual SKU details
router.get('/:skuId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  // Find SKU to ensure it exists and belongs to user's company
  const sku = await prisma.sKU.findFirst({
    where: {
      id: skuId,
    },
    include: {
      coilItems: {
        include: {
          coil: {
            include: {
              machine: {
                include: {
                  company: true,
                },
              },
            },
          },
        },
      },
    },
  });

  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }

  // Check if SKU belongs to user's company through any coil item
  const belongsToCompany = sku.coilItems.some(coilItem => 
    coilItem.coil.machine?.companyId === req.auth!.companyId
  );

  if (!belongsToCompany) {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  return res.json({
    id: sku.id,
    code: sku.code,
    name: sku.name,
    type: sku.type,
    category: sku.category,
    isCheeseAndCrackers: sku.isCheeseAndCrackers,
    countNeededPointer: sku.countNeededPointer,
  });
});

// Get SKU statistics
router.get('/:skuId/stats', setLogConfig({ level: 'full' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  const timezoneOverride = parseTimezoneQueryParam(req.query.timezone);
  if (timezoneOverride && !isValidTimezone(timezoneOverride)) {
    return res.status(400).json({
      error: 'Invalid timezone supplied. Please use an IANA timezone like "America/Chicago".',
    });
  }

  if (!req.auth!.companyId) {
    return res.status(403).json({ error: 'User must belong to a company' });
  }

  const now = new Date();
  const timeZone: string = await resolveCompanyTimezone(req.auth!.companyId, timezoneOverride);

  const sku = await prisma.sKU.findUnique({
    where: { id: skuId },
    include: {
      coilItems: {
        include: {
          coil: {
            include: {
              machine: true,
            },
          },
        },
      },
    },
  });

  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }

  const belongsToCompany = sku.coilItems.some(coilItem =>
    coilItem.coil.machine?.companyId === req.auth!.companyId
  );

  if (!belongsToCompany) {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  const periodQuery =
    typeof req.query.period === 'string' ? req.query.period.toLowerCase() : undefined;
  const period =
    periodQuery === 'week' || periodQuery === 'month' || periodQuery === 'quarter'
      ? (periodQuery as SkuStatsPeriod)
      : 'week';
  const periodRange = buildPeriodRange(period, now, timeZone);
  const periodStart = periodRange.start;
  const periodEnd = periodRange.end;
  const periodDurationMs = periodEnd.getTime() - periodStart.getTime();
  const periodDays = periodRange.dayCount || PERIOD_DAY_COUNTS[period];
  const elapsedMs = Math.max(0, Math.min(periodDurationMs, now.getTime() - periodStart.getTime()));
  const previousWindowEnd = new Date(periodStart);
  const previousWindowStart = new Date(periodStart.getTime() - elapsedMs);

  const { points, totalItems } = await buildSkuChartPoints(
    skuId,
    periodStart,
    new Date(Math.min(now.getTime(), periodEnd.getTime())),
    req.auth!.companyId,
    timeZone,
    periodDays,
  );

  const previousTotal =
    elapsedMs > 0
      ? await getSkuTotalPicks(skuId, previousWindowStart, previousWindowEnd, req.auth!.companyId)
      : 0;

  const percentageChange =
    elapsedMs > 0 ? buildPercentageChange(totalItems, previousTotal) : null;
  const bestMachine = await getSkuBestMachine(skuId, req.auth!.companyId);
  const mostRecentPick = await getMostRecentPick(skuId, req.auth!.companyId);

  return res.json({
    generatedAt: new Date().toISOString(),
    timeZone,
    period,
    rangeStart: periodStart.toISOString(),
    rangeEnd: now.toISOString(),
    lookbackDays: periodDays,
    progress: {
      elapsedSeconds: Math.round(elapsedMs / 1000),
      periodSeconds: Math.round(periodDurationMs / 1000),
      ratio: periodDurationMs > 0 ? Number((elapsedMs / periodDurationMs).toFixed(3)) : 0,
    },
    percentageChange,
    bestMachine,
    points,
    mostRecentPick,
  });
});

async function getMostRecentPick(skuId: string, companyId: string) {
  const result = await prisma.$queryRaw<Array<{
    pickedAt: Date;
    locationName: string;
    runId: string;
  }>>(
    Prisma.sql`
      SELECT 
        pe.pickedAt,
        loc.name AS locationName,
        r.id AS runId
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      LEFT JOIN Location loc ON loc.id = mach.locationId
      JOIN Run r ON r.id = pe.runId
      WHERE ci.skuId = ${skuId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND r.companyId = ${companyId}
      ORDER BY pe.pickedAt DESC
      LIMIT 1
    `
  );

  if (result.length === 0) {
    return null;
  }

  const row = result[0];
  if (!row) {
    return null;
  }

  return {
    pickedAt: row.pickedAt.toISOString(),
    locationName: row.locationName || 'Unknown',
    runId: row.runId,
  };
}

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

type SkuStatsPeriod = 'week' | 'month' | 'quarter';

const PERIOD_DAY_COUNTS: Record<SkuStatsPeriod, number> = {
  week: 7,
  month: 30,
  quarter: 90,
};

type ChartRow = {
  date: string;
  machineId: string;
  machineCode: string;
  machineName: string | null;
  totalPicked: bigint;
};

type ChartPoint = {
  date: string;
  totalItems: number;
  machines: Array<{
    machineId: string;
    machineCode: string;
    machineName: string | null;
    count: number;
  }>;
};

async function buildSkuChartPoints(
  skuId: string,
  startDate: Date,
  endDate: Date,
  companyId: string,
  timeZone: string,
  periodDays: number,
) {
  const rows = await prisma.$queryRaw<Array<ChartRow>>(
    Prisma.sql`
      SELECT 
        DATE_FORMAT(CONVERT_TZ(pe.pickedAt, 'UTC', ${timeZone}), '%Y-%m-%d') AS date,
        mach.id AS machineId,
        mach.code AS machineCode,
        mach.description AS machineName,
        SUM(pe.count) AS totalPicked
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      JOIN Run r ON r.id = pe.runId
      WHERE ci.skuId = ${skuId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND pe.pickedAt >= ${startDate}
        AND pe.pickedAt < ${endDate}
        AND r.companyId = ${companyId}
      GROUP BY date, mach.id, mach.code, mach.description
      ORDER BY date ASC, mach.code ASC
    `,
  );

  const machinesByDate = new Map<
    string,
    Map<string, { machineCode: string; machineName: string | null; count: number }>
  >();

  for (const row of rows) {
    const date = row.date;
    const dateBucket = machinesByDate.get(date) ?? new Map();
    const existing = dateBucket.get(row.machineId);
    const count = Number(row.totalPicked);

    dateBucket.set(row.machineId, {
      machineCode: row.machineCode,
      machineName: row.machineName,
      count: (existing?.count ?? 0) + count,
    });

    machinesByDate.set(date, dateBucket);
  }

  const labels = buildPeriodLabels(startDate, periodDays, timeZone);
  const points: ChartPoint[] = labels.map(date => {
    const bucket = machinesByDate.get(date);
    const machines = bucket
      ? Array.from(bucket.entries()).map(([machineId, machineData]) => ({
          machineId,
          machineCode: machineData.machineCode,
          machineName: machineData.machineName,
          count: machineData.count,
        }))
      : [];

    const totalItems = machines.reduce((sum, machine) => sum + machine.count, 0);
    return {
      date,
      totalItems,
      machines,
    };
  });

  const totalItems = points.reduce((sum, point) => sum + point.totalItems, 0);
  return { points, totalItems };
}

async function getSkuTotalPicks(
  skuId: string,
  startDate: Date,
  endDate: Date,
  companyId: string,
) {
  const result = await prisma.$queryRaw<Array<{ totalPicked: bigint }>>(
    Prisma.sql`
      SELECT SUM(pe.count) AS totalPicked
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Run r ON r.id = pe.runId
      WHERE ci.skuId = ${skuId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND pe.pickedAt >= ${startDate}
        AND pe.pickedAt < ${endDate}
        AND r.companyId = ${companyId}
    `,
  );

  return Number(result[0]?.totalPicked ?? 0);
}

async function getSkuBestMachine(skuId: string, companyId: string) {
  const result = await prisma.$queryRaw<Array<{
    machineId: string;
    machineCode: string;
    machineName: string | null;
    totalPicked: bigint;
  }>>(
    Prisma.sql`
      SELECT 
        mach.id AS machineId,
        mach.code AS machineCode,
        mach.description AS machineName,
        SUM(pe.count) AS totalPicked
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      JOIN Run r ON r.id = pe.runId
      WHERE ci.skuId = ${skuId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND r.companyId = ${companyId}
      GROUP BY mach.id, mach.code, mach.description
      ORDER BY totalPicked DESC
      LIMIT 1
    `,
  );

  if (result.length === 0) {
    return null;
  }

  const row = result[0]!;
  return {
    machineId: row.machineId,
    machineCode: row.machineCode,
    machineName: row.machineName,
    totalPacks: Number(row.totalPicked),
  };
}

function buildPercentageChange(currentTotal: number, previousTotal: number) {
  if (currentTotal === 0 && previousTotal === 0) {
    return null;
  }

  if (previousTotal === 0 && currentTotal > 0) {
    return { value: 100, trend: 'up' as const };
  }

  if (previousTotal > 0 && currentTotal === 0) {
    return { value: -100, trend: 'down' as const };
  }

  const percentageChange = ((currentTotal - previousTotal) / previousTotal) * 100;
  const trend =
    percentageChange > 0.5 ? 'up' : percentageChange < -0.5 ? 'down' : 'neutral';

  return {
    value: Math.round(percentageChange * 10) / 10,
    trend,
  };
}

function buildPeriodLabels(startDate: Date, periodDays: number, timeZone: string): string[] {
  const labels: string[] = [];
  const cursor = new Date(startDate);

  for (let i = 0; i < periodDays; i += 1) {
    labels.push(formatDateInTimezone(cursor, timeZone));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }

  return labels;
}

function buildPeriodRange(period: SkuStatsPeriod, reference: Date, timeZone: string) {
  const todayRange = getTimezoneDayRange({ timeZone, dayOffset: 0, reference });
  const { year, month } = getLocalDateParts(reference, timeZone);

  let start: Date;
  switch (period) {
    case 'week': {
      const weekday = getWeekdayIndexInTimezone(reference, timeZone);
      const offsetFromMonday = (weekday + 6) % 7;
      start = new Date(todayRange.start);
      start.setUTCDate(start.getUTCDate() - offsetFromMonday);
      break;
    }
    case 'month': {
      const candidate = new Date(Date.UTC(year, month - 1, 1));
      start = convertDateToTimezoneMidnight(candidate, timeZone);
      break;
    }
    case 'quarter': {
      const quarterStartMonth = Math.floor((month - 1) / 3) * 3;
      const candidate = new Date(Date.UTC(year, quarterStartMonth, 1));
      start = convertDateToTimezoneMidnight(candidate, timeZone);
      break;
    }
  }

  const end = new Date(start);
  switch (period) {
    case 'week':
      end.setUTCDate(end.getUTCDate() + 7);
      break;
    case 'month':
      end.setUTCMonth(end.getUTCMonth() + 1);
      break;
    case 'quarter':
      end.setUTCMonth(end.getUTCMonth() + 3);
      break;
  }

  const dayCount = Math.round((end.getTime() - start.getTime()) / ONE_DAY_MS);
  return { start, end, dayCount };
}

export const skuRouter = router;
