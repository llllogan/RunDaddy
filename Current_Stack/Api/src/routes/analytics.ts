import { Router } from 'express';
import type { Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { getTimezoneDayRange, isValidTimezone } from '../lib/timezone.js';
import type { TimezoneDayRange } from '../lib/timezone.js';
import { parseTimezoneQueryParam, resolveCompanyTimezone } from './helpers/timezone.js';

const LOOKBACK_DEFAULT = 30;
const LOOKBACK_MIN = 7;
const LOOKBACK_MAX = 90;
const DAY_IN_MS = 24 * 60 * 60 * 1000;

const WEEKDAY_INDEX: Record<string, number> = {
  Sun: 0,
  Mon: 1,
  Tue: 2,
  Wed: 3,
  Thu: 4,
  Fri: 5,
  Sat: 6,
};

type DailyRow = {
  day_label: string | null;
  total_items: bigint | number | string | null;
};

type LocationMachineRow = {
  location_id: string | null;
  location_name: string | null;
  machine_id: string | null;
  machine_code: string | null;
  total_items: bigint | number | string | null;
};

type SkuRow = {
  sku_id: string;
  sku_name: string;
  sku_code: string;
  total_items: bigint | number | string | null;
};

const router = Router();

router.use(authenticate);

router.get('/daily-totals', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildLookbackContext(req, res);
  if (!context) {
    return;
  }

  const dailyRows = await fetchDailyRows(
    context.companyId,
    context.rangeStart,
    context.rangeEnd,
    context.timeZone,
  );
  const points = buildDailySeries(context.dayRanges, dailyRows);

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays: context.lookbackDays,
    rangeStart: context.rangeStart.toISOString(),
    rangeEnd: context.rangeEnd.toISOString(),
    points,
  });
});

router.get('/locations/top', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildLookbackContext(req, res);
  if (!context) {
    return;
  }

  const rows = await fetchLocationMachineRows(context.companyId, context.rangeStart, context.rangeEnd);
  const locations = buildTopLocations(rows);

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays: context.lookbackDays,
    rangeStart: context.rangeStart.toISOString(),
    rangeEnd: context.rangeEnd.toISOString(),
    locations,
  });
});

router.get('/skus/top', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildLookbackContext(req, res);
  if (!context) {
    return;
  }

  const rows = await fetchSkuRows(context.companyId, context.rangeStart, context.rangeEnd);
  const skuBreakdown = buildSkuBreakdown(rows);
  const topSkus = skuBreakdown.slice(0, 5);

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays: context.lookbackDays,
    rangeStart: context.rangeStart.toISOString(),
    rangeEnd: context.rangeEnd.toISOString(),
    skus: topSkus,
  });
});

router.get('/skus/breakdown', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildLookbackContext(req, res);
  if (!context) {
    return;
  }

  const rows = await fetchSkuRows(context.companyId, context.rangeStart, context.rangeEnd);
  const breakdown = buildSkuBreakdown(rows);
  const totalItems = breakdown.reduce((sum, sku) => sum + sku.totalItems, 0);

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays: context.lookbackDays,
    rangeStart: context.rangeStart.toISOString(),
    rangeEnd: context.rangeEnd.toISOString(),
    totalItems,
    breakdown,
  });
});

router.get('/average-daily', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildLookbackContext(req, res);
  if (!context) {
    return;
  }

  const dailyRows = await fetchDailyRows(
    context.companyId,
    context.rangeStart,
    context.rangeEnd,
    context.timeZone,
  );
  const points = buildDailySeries(context.dayRanges, dailyRows);
  const nonZeroDays = points.filter((day) => day.totalItems > 0);
  const totalOnActiveDays = nonZeroDays.reduce((sum, day) => sum + day.totalItems, 0);

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays: context.lookbackDays,
    rangeStart: context.rangeStart.toISOString(),
    rangeEnd: context.rangeEnd.toISOString(),
    value:
      nonZeroDays.length > 0
        ? Number((totalOnActiveDays / nonZeroDays.length).toFixed(2))
        : 0,
    activeDays: nonZeroDays.length,
  });
});

router.get('/week-over-week', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildTimezoneContext(req, res);
  if (!context) {
    return;
  }

  const currentWeekStart = getIsoWeekStart(context.timeZone, context.now);
  const currentPeriodEnd = context.now;
  const currentWeekDuration = Math.max(0, currentPeriodEnd.getTime() - currentWeekStart.getTime());
  const previousWeekStart = new Date(currentWeekStart.getTime() - 7 * DAY_IN_MS);
  const previousPeriodEnd = new Date(previousWeekStart.getTime() + currentWeekDuration);

  const [currentWeekTotal, previousWeekTotal] = await Promise.all([
    sumPackedItems(context.companyId, currentWeekStart, currentPeriodEnd),
    sumPackedItems(context.companyId, previousWeekStart, previousPeriodEnd),
  ]);

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    currentPeriod: {
      start: currentWeekStart.toISOString(),
      end: currentPeriodEnd.toISOString(),
      totalItems: currentWeekTotal,
    },
    previousPeriod: {
      start: previousWeekStart.toISOString(),
      end: previousPeriodEnd.toISOString(),
      totalItems: previousWeekTotal,
    },
    growthPercentage:
      previousWeekTotal === 0
        ? null
        : Number((((currentWeekTotal - previousWeekTotal) / previousWeekTotal) * 100).toFixed(2)),
  });
});

type LookbackContext = {
  companyId: string;
  timeZone: string;
  now: Date;
  lookbackDays: number;
  dayRanges: TimezoneDayRange[];
  rangeStart: Date;
  rangeEnd: Date;
};

type TimezoneContext = {
  companyId: string;
  timeZone: string;
  now: Date;
};

async function buildLookbackContext(req: Request, res: Response): Promise<LookbackContext | null> {
  const timezoneContext = await buildTimezoneContext(req, res);
  if (!timezoneContext) {
    return null;
  }

  const lookbackDays = parseLookbackDays(req.query.lookbackDays);
  const dayRanges = buildDayRanges(timezoneContext.timeZone, lookbackDays, timezoneContext.now);

  if (dayRanges.length === 0) {
    res.status(400).json({ error: 'Unable to construct lookback window' });
    return null;
  }

  return {
    ...timezoneContext,
    lookbackDays,
    dayRanges,
    rangeStart: dayRanges[0]!.start,
    rangeEnd: dayRanges[dayRanges.length - 1]!.end,
  };
}

async function buildTimezoneContext(req: Request, res: Response): Promise<TimezoneContext | null> {
  if (!req.auth) {
    res.status(401).json({ error: 'Unauthorized' });
    return null;
  }

  if (!req.auth.companyId) {
    res.status(403).json({ error: 'Company membership required for analytics' });
    return null;
  }

  const timezoneOverride = parseTimezoneQueryParam(req.query.timezone);
  if (timezoneOverride && !isValidTimezone(timezoneOverride)) {
    res.status(400).json({
      error: 'Invalid timezone supplied. Please use an IANA timezone like "America/Chicago".',
    });
    return null;
  }

  const now = new Date();
  const timeZone = await resolveCompanyTimezone(req.auth.companyId, timezoneOverride);

  return {
    companyId: req.auth.companyId,
    timeZone,
    now,
  };
}

function parseLookbackDays(value: unknown): number {
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return clamp(parsed, LOOKBACK_MIN, LOOKBACK_MAX);
    }
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return clamp(Math.trunc(value), LOOKBACK_MIN, LOOKBACK_MAX);
  }
  return LOOKBACK_DEFAULT;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function buildDayRanges(timeZone: string, lookbackDays: number, reference: Date): TimezoneDayRange[] {
  const ranges: TimezoneDayRange[] = [];
  for (let offset = lookbackDays - 1; offset >= 0; offset -= 1) {
    ranges.push(getTimezoneDayRange({ timeZone, dayOffset: -offset, reference }));
  }
  return ranges;
}

async function fetchDailyRows(
  companyId: string,
  rangeStart: Date,
  rangeEnd: Date,
  timeZone: string,
) {
  return prisma.$queryRaw<DailyRow[]>(
    Prisma.sql`
      SELECT
        DATE(CONVERT_TZ(pe.pickedAt, '+00:00', ${timeZone})) AS day_label,
        SUM(pe.count) AS total_items
      FROM PickEntry pe
      JOIN Run r ON r.id = pe.runId
      WHERE r.companyId = ${companyId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND pe.pickedAt >= ${rangeStart}
        AND pe.pickedAt < ${rangeEnd}
      GROUP BY day_label
      ORDER BY day_label ASC
    `,
  );
}

async function fetchLocationMachineRows(companyId: string, rangeStart: Date, rangeEnd: Date) {
  return prisma.$queryRaw<LocationMachineRow[]>(
    Prisma.sql`
      SELECT
        loc.id AS location_id,
        loc.name AS location_name,
        mach.id AS machine_id,
        mach.code AS machine_code,
        SUM(pe.count) AS total_items
      FROM PickEntry pe
      JOIN Run r ON r.id = pe.runId
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      JOIN Location loc ON loc.id = mach.locationId
      WHERE r.companyId = ${companyId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND pe.pickedAt >= ${rangeStart}
        AND pe.pickedAt < ${rangeEnd}
      GROUP BY loc.id, loc.name, mach.id, mach.code
      HAVING SUM(pe.count) > 0
    `,
  );
}

async function fetchSkuRows(companyId: string, rangeStart: Date, rangeEnd: Date) {
  return prisma.$queryRaw<SkuRow[]>(
    Prisma.sql`
      SELECT
        sku.id AS sku_id,
        sku.name AS sku_name,
        sku.code AS sku_code,
        SUM(pe.count) AS total_items
      FROM PickEntry pe
      JOIN Run r ON r.id = pe.runId
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN SKU sku ON sku.id = ci.skuId
      WHERE r.companyId = ${companyId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND pe.pickedAt >= ${rangeStart}
        AND pe.pickedAt < ${rangeEnd}
      GROUP BY sku.id, sku.name, sku.code
      HAVING SUM(pe.count) > 0
      ORDER BY total_items DESC
    `,
  );
}

function buildDailySeries(dayRanges: TimezoneDayRange[], rows: DailyRow[]) {
  const totalsByLabel = new Map<string, number>();
  for (const row of rows) {
    if (!row.day_label) {
      continue;
    }
    totalsByLabel.set(row.day_label, toNumber(row.total_items));
  }

  return dayRanges.map((range) => ({
    date: range.label,
    start: range.start.toISOString(),
    end: range.end.toISOString(),
    totalItems: totalsByLabel.get(range.label) ?? 0,
  }));
}

function buildTopLocations(rows: LocationMachineRow[]) {
  const locations = new Map<
    string,
    {
      locationId: string;
      locationName: string;
      totalItems: number;
      machines: Map<
        string,
        {
          machineId: string;
          machineCode: string;
          totalItems: number;
        }
      >;
    }
  >();

  for (const row of rows) {
    if (!row.location_id || !row.machine_id) {
      continue;
    }
    const total = toNumber(row.total_items);
    if (total <= 0) {
      continue;
    }

    if (!locations.has(row.location_id)) {
      locations.set(row.location_id, {
        locationId: row.location_id,
        locationName: row.location_name ?? 'Unknown location',
        totalItems: 0,
        machines: new Map(),
      });
    }

    const locationEntry = locations.get(row.location_id)!;
    locationEntry.totalItems += total;

    if (!locationEntry.machines.has(row.machine_id)) {
      locationEntry.machines.set(row.machine_id, {
        machineId: row.machine_id,
        machineCode: row.machine_code ?? 'Unknown',
        totalItems: 0,
      });
    }
    const machineEntry = locationEntry.machines.get(row.machine_id)!;
    machineEntry.totalItems += total;
  }

  return Array.from(locations.values())
    .sort((a, b) => b.totalItems - a.totalItems)
    .slice(0, 3)
    .map((location) => ({
      locationId: location.locationId,
      locationName: location.locationName,
      totalItems: location.totalItems,
      machines: Array.from(location.machines.values()).sort((a, b) => b.totalItems - a.totalItems),
    }));
}

function buildSkuBreakdown(rows: SkuRow[]) {
  const totals = rows
    .map((row) => ({
      skuId: row.sku_id,
      skuName: row.sku_name,
      skuCode: row.sku_code,
      totalItems: toNumber(row.total_items),
    }))
    .filter((row) => row.totalItems > 0);

  const aggregateTotal = totals.reduce((sum, row) => sum + row.totalItems, 0);

  return totals.map((row) => ({
    ...row,
    percentage: aggregateTotal > 0 ? Number(((row.totalItems / aggregateTotal) * 100).toFixed(2)) : 0,
  }));
}

async function sumPackedItems(companyId: string, rangeStart: Date, rangeEnd: Date): Promise<number> {
  const [row] = await prisma.$queryRaw<{ total_items: bigint | number | string | null }[]>(
    Prisma.sql`
      SELECT COALESCE(SUM(pe.count), 0) AS total_items
      FROM PickEntry pe
      JOIN Run r ON r.id = pe.runId
      WHERE r.companyId = ${companyId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND pe.pickedAt >= ${rangeStart}
        AND pe.pickedAt < ${rangeEnd}
    `,
  );

  return toNumber(row?.total_items ?? 0);
}

function getIsoWeekStart(timeZone: string, reference: Date): Date {
  const weekdayFormatter = new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone });
  const weekdayName = weekdayFormatter.format(reference);
  const weekdayIndex = WEEKDAY_INDEX[weekdayName] ?? 0;
  const daysSinceMonday = (weekdayIndex + 6) % 7; // Convert Sunday-based index to Monday-based
  const todayRange = getTimezoneDayRange({ timeZone, dayOffset: 0, reference });
  return new Date(todayRange.start.getTime() - daysSinceMonday * DAY_IN_MS);
}

function toNumber(value: unknown): number {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'bigint') {
    return Number(value);
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

export const analyticsRouter = router;
