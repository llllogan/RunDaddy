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
router.get('/:skuId/stats', setLogConfig({ level: 'minimal' }), async (req, res) => {
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
  const periodDays = PERIOD_DAY_COUNTS[period];
  const chartRange = buildChartRange(period, periodRange, timeZone);
  const dataEnd = new Date(
    Math.min(now.getTime(), chartRange.end.getTime()),
  );
  const elapsedMs = Math.max(0, Math.min(periodDurationMs, now.getTime() - periodStart.getTime()));
  const previousWindowEnd = new Date(periodStart);
  const previousWindowStart = new Date(periodStart.getTime() - elapsedMs);

  const { points, totalItems } = await buildSkuChartPoints(
    skuId,
    chartRange.start,
    chartRange.end,
    dataEnd,
    req.auth!.companyId,
    timeZone,
    period,
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
    scheduledFor: Date | null;
    locationName: string;
    runId: string;
  }>>(
    Prisma.sql`
      SELECT 
        r.scheduledFor,
        loc.name AS locationName,
        r.id AS runId
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      LEFT JOIN Location loc ON loc.id = mach.locationId
      JOIN Run r ON r.id = pe.runId
      WHERE ci.skuId = ${skuId}
        AND r.scheduledFor IS NOT NULL
        AND r.companyId = ${companyId}
      ORDER BY r.scheduledFor DESC
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
    pickedAt: row.scheduledFor?.toISOString() ?? new Date().toISOString(),
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

type PeriodBucket = {
  key: string;
  label: string;
  start: Date;
  end: Date;
  startMs: number;
  endMs: number;
};

async function buildSkuChartPoints(
  skuId: string,
  chartStart: Date,
  chartEnd: Date,
  dataEnd: Date,
  companyId: string,
  timeZone: string,
  period: SkuStatsPeriod,
) {
  const rows = await prisma.$queryRaw<Array<ChartRow>>(
    Prisma.sql`
      SELECT 
        DATE_FORMAT(CONVERT_TZ(r.scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS date,
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
        AND r.scheduledFor IS NOT NULL
        AND r.scheduledFor >= ${chartStart}
        AND r.scheduledFor < ${dataEnd}
        AND r.companyId = ${companyId}
      GROUP BY date, mach.id, mach.code, mach.description
      ORDER BY date ASC, mach.code ASC
    `,
  );

  const buckets = buildChartBuckets(period, chartStart, chartEnd, timeZone);

  const bucketTotals = new Map<string, number>();
  const bucketMachines = new Map<
    string,
    Map<string, { machineCode: string; machineName: string | null; count: number }>
  >();

  for (const row of rows) {
    const rowDate = parseLocalDate(row.date, timeZone).getTime();
    const bucket = buckets.find(b => rowDate >= b.startMs && rowDate < b.endMs);
    if (!bucket) {
      continue;
    }

    const count = Number(row.totalPicked);
    const machinesForBucket = bucketMachines.get(bucket.key) ?? new Map();
    const existing = machinesForBucket.get(row.machineId);

    machinesForBucket.set(row.machineId, {
      machineCode: row.machineCode,
      machineName: row.machineName,
      count: (existing?.count ?? 0) + count,
    });

    bucketMachines.set(bucket.key, machinesForBucket);
    bucketTotals.set(bucket.key, (bucketTotals.get(bucket.key) ?? 0) + count);
  }

  const points: ChartPoint[] = buckets.map(bucket => {
    const machinesForBucket = bucketMachines.get(bucket.key);
    const machines = machinesForBucket
      ? Array.from(machinesForBucket.entries()).map(([machineId, machineData]) => ({
          machineId,
          machineCode: machineData.machineCode,
          machineName: machineData.machineName,
          count: machineData.count,
        }))
      : [];

    const totalItems = bucketTotals.get(bucket.key) ?? 0;
    return {
      date: bucket.label,
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
        AND r.scheduledFor IS NOT NULL
        AND r.scheduledFor >= ${startDate}
        AND r.scheduledFor < ${endDate}
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

function buildChartRange(
  period: SkuStatsPeriod,
  periodRange: { start: Date; end: Date },
  timeZone: string,
) {
  if (period === 'month') {
    const start = getWeekStart(periodRange.start, timeZone);
    const endWeekStart = getWeekStart(periodRange.end, timeZone);
    const end = new Date(endWeekStart);
    end.setUTCDate(end.getUTCDate() + 7);
    return { start, end };
  }

  return {
    start: new Date(periodRange.start),
    end: new Date(periodRange.end),
  };
}

function buildChartBuckets(
  period: SkuStatsPeriod,
  chartStart: Date,
  chartEnd: Date,
  timeZone: string,
) {
  switch (period) {
    case 'week':
      return buildDailyBuckets(chartStart, chartEnd, timeZone);
    case 'month':
      return buildWeeklyBuckets(chartStart, chartEnd, timeZone);
    case 'quarter':
      return buildMonthlyBuckets(chartStart, chartEnd, timeZone);
    default:
      return buildDailyBuckets(chartStart, chartEnd, timeZone);
  }
}

function buildDailyBuckets(start: Date, end: Date, timeZone: string): PeriodBucket[] {
  const buckets: PeriodBucket[] = [];
  let cursor = new Date(start);

  while (cursor < end) {
    const bucketStart = new Date(cursor);
    const bucketEnd = new Date(bucketStart);
    bucketEnd.setUTCDate(bucketEnd.getUTCDate() + 1);

    buckets.push(
      createBucket(formatDateInTimezone(bucketStart, timeZone), bucketStart, bucketEnd),
    );

    cursor = bucketEnd;
  }

  return buckets;
}

function buildWeeklyBuckets(start: Date, end: Date, timeZone: string): PeriodBucket[] {
  const buckets: PeriodBucket[] = [];
  let cursor = getWeekStart(start, timeZone);

  while (cursor < end) {
    const bucketStart = new Date(cursor);
    const bucketEnd = new Date(bucketStart);
    bucketEnd.setUTCDate(bucketEnd.getUTCDate() + 7);

    buckets.push(
      createBucket(formatDateInTimezone(bucketStart, timeZone), bucketStart, bucketEnd),
    );

    cursor = bucketEnd;
  }

  return buckets;
}

function buildMonthlyBuckets(start: Date, end: Date, timeZone: string): PeriodBucket[] {
  const buckets: PeriodBucket[] = [];
  let cursor = getMonthStart(start, timeZone);

  while (cursor < end) {
    const bucketStart = new Date(cursor);
    const bucketEnd = getNextMonthStart(bucketStart, timeZone);

    buckets.push(createBucket(formatMonthName(bucketStart, timeZone), bucketStart, bucketEnd));
    cursor = bucketEnd;
  }

  return buckets;
}

function createBucket(label: string, start: Date, end: Date): PeriodBucket {
  return {
    key: start.toISOString(),
    label,
    start,
    end,
    startMs: start.getTime(),
    endMs: end.getTime(),
  };
}

function getWeekStart(date: Date, timeZone: string): Date {
  const weekday = getWeekdayIndexInTimezone(date, timeZone);
  const offsetFromMonday = (weekday + 6) % 7;
  const start = new Date(date);
  start.setUTCDate(start.getUTCDate() - offsetFromMonday);
  return start;
}

const MONTH_NAME_FORMATTER_CACHE = new Map<string, Intl.DateTimeFormat>();

function formatMonthName(date: Date, timeZone: string) {
  const key = `${timeZone}-month`;
  if (!MONTH_NAME_FORMATTER_CACHE.has(key)) {
    MONTH_NAME_FORMATTER_CACHE.set(
      key,
      new Intl.DateTimeFormat('en-US', { month: 'long', timeZone }),
    );
  }
  return MONTH_NAME_FORMATTER_CACHE.get(key)!.format(date);
}

function parseLocalDate(dateString: string, timeZone: string): Date {
  const [year, month, day] = dateString.split('-').map(part => Number(part));
  const candidate = new Date(Date.UTC(year, month - 1, day));
  return convertDateToTimezoneMidnight(candidate, timeZone);
}

function getMonthStart(date: Date, timeZone: string): Date {
  const { year, month } = getLocalDateParts(date, timeZone);
  const candidate = new Date(Date.UTC(year, month - 1, 1));
  return convertDateToTimezoneMidnight(candidate, timeZone);
}

function getNextMonthStart(date: Date, timeZone: string): Date {
  const { year, month } = getLocalDateParts(date, timeZone);
  const candidate = new Date(Date.UTC(year, month, 1));
  return convertDateToTimezoneMidnight(candidate, timeZone);
}

export const skuRouter = router;
