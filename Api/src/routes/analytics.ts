import { Router } from 'express';
import type { Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { getTimezoneDayRange, isValidTimezone, formatDateInTimezone } from '../lib/timezone.js';
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
  day_label: string | Date | null;
  total_items: bigint | number | string | null;
  items_packed: bigint | number | string | null;
};

type LocationMachineRow = {
  location_id: string | null;
  location_name: string | null;
  machine_id: string | null;
  machine_code: string | null;
  machine_description: string | null;
  total_items: bigint | number | string | null;
  location_total: bigint | number | string | null;
};

type SkuRow = {
  sku_id: string;
  sku_name: string;
  sku_code: string;
  total_items: bigint | number | string | null;
};

const router = Router();

router.use(authenticate);

router.get('/daily-totals', setLogConfig({ level: 'full' }), async (req, res) => {
  const context = await buildLookbackContext(req, res);
  if (!context) {
    return;
  }

  const dailyRows = await fetchDailyRows(context.companyId, context.lookbackDays, context.timeZone);
  const dayRangesWithTomorrow = appendTomorrowRange(context.dayRanges, context.timeZone, context.now);
  const points = buildDailySeries(dayRangesWithTomorrow, dailyRows);
  const responseRangeEnd =
    dayRangesWithTomorrow[dayRangesWithTomorrow.length - 1]?.end ?? context.rangeEnd;

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays: context.lookbackDays,
    rangeStart: context.rangeStart.toISOString(),
    rangeEnd: responseRangeEnd.toISOString(),
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

  const dailyRows = await fetchDailyRows(context.companyId, context.lookbackDays, context.timeZone);
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

  // Build the trailing window so it always ends with the active (current) day,
  // then trim to the requested lookback size. This guarantees callers receive
  // today's bucket even while the day is still in progress.
  for (let offset = lookbackDays; offset >= 1; offset -= 1) {
    ranges.push(getTimezoneDayRange({ timeZone, dayOffset: -offset, reference }));
  }
  ranges.push(getTimezoneDayRange({ timeZone, dayOffset: 0, reference }));

  if (ranges.length > lookbackDays) {
    return ranges.slice(ranges.length - lookbackDays);
  }
  return ranges;
}

function appendTomorrowRange(
  dayRanges: TimezoneDayRange[],
  timeZone: string,
  reference: Date,
): TimezoneDayRange[] {
  const tomorrowRange = getTimezoneDayRange({ timeZone, dayOffset: 1, reference });
  if (dayRanges.some((range) => range.label === tomorrowRange.label)) {
    return dayRanges;
  }
  return [...dayRanges, tomorrowRange];
}

async function fetchDailyRows(companyId: string, lookbackDays: number, timeZone: string) {
  const trailingDays = Math.max(lookbackDays - 1, 0);

  return prisma.$queryRaw<DailyRow[]>(
    Prisma.sql`
      SELECT day_label, total_items, items_packed
      FROM (
        SELECT 
          converted_date AS day_label,
          SUM(total_items) AS total_items,
          SUM(items_packed) AS items_packed
        FROM (
          SELECT
            DATE_FORMAT(CONVERT_TZ(r.scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS converted_date,
            pe.count AS total_items,
            CASE WHEN pe.status = 'PICKED' THEN pe.count ELSE 0 END AS items_packed
          FROM PickEntry pe
          JOIN Run r ON r.id = pe.runId
          WHERE r.companyId = ${companyId}
            AND CONVERT_TZ(r.scheduledFor, 'UTC', ${timeZone}) >= DATE_SUB(CONVERT_TZ(CURRENT_TIMESTAMP(), 'UTC', ${timeZone}), INTERVAL ${Prisma.raw(String(trailingDays))} DAY)
            AND CONVERT_TZ(r.scheduledFor, 'UTC', ${timeZone}) < DATE_ADD(CONVERT_TZ(CURRENT_TIMESTAMP(), 'UTC', ${timeZone}), INTERVAL 2 DAY)
        ) AS converted_data
        GROUP BY converted_date
      ) AS daily_totals
      ORDER BY day_label ASC
    `,
  );
}

async function fetchLocationMachineRows(companyId: string, rangeStart: Date, rangeEnd: Date) {
  return prisma.$queryRaw<LocationMachineRow[]>(
    Prisma.sql`
      WITH machine_totals AS (
        SELECT
          loc.id AS location_id,
          loc.name AS location_name,
          mach.id AS machine_id,
          mach.code AS machine_code,
          mach.description AS machine_description,
          SUM(pe.count) AS total_items
        FROM PickEntry pe
        JOIN Run r ON r.id = pe.runId
        JOIN CoilItem ci ON ci.id = pe.coilItemId
        JOIN Coil coil ON coil.id = ci.coilId
        JOIN Machine mach ON mach.id = coil.machineId
        JOIN Location loc ON loc.id = mach.locationId
        WHERE r.companyId = ${companyId}
          AND r.scheduledFor >= ${rangeStart}
          AND r.scheduledFor < ${rangeEnd}
        GROUP BY loc.id, loc.name, mach.id, mach.code
        HAVING SUM(pe.count) > 0
      ),
      location_totals AS (
        SELECT
          location_id,
          SUM(total_items) AS location_total
        FROM machine_totals
        GROUP BY location_id
      ),
      top_locations AS (
        SELECT
          location_id
        FROM location_totals
        ORDER BY location_total DESC
        LIMIT 3
      )
      SELECT
        mt.location_id,
        mt.location_name,
        mt.machine_id,
        mt.machine_code,
        mt.machine_description,
        mt.total_items,
        lt.location_total
      FROM machine_totals mt
      JOIN top_locations tl ON tl.location_id = mt.location_id
      JOIN location_totals lt ON lt.location_id = mt.location_id
      ORDER BY lt.location_total DESC, mt.total_items DESC
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
  const targetTimeZone = dayRanges[0]?.timeZone ?? 'UTC';
  const totalsByLabel = new Map<string, number>();
  const packedByLabel = new Map<string, number>();

  for (const row of rows) {
    const normalizedLabel = normalizeDayLabel(row.day_label, targetTimeZone);
    if (!normalizedLabel) {
      continue;
    }
    totalsByLabel.set(normalizedLabel, toNumber(row.total_items));
    packedByLabel.set(normalizedLabel, toNumber(row.items_packed));
  }

  return dayRanges.map((range) => {
    // Create a date that will display as the local date when interpreted in the client's timezone
    const parts = range.label.split('-').map(Number);
    const year = parts[0] ?? 0;
    const month = (parts[1] ?? 1) - 1; // Convert to 0-based month
    const day = parts[2] ?? 1;
    const baseDate = new Date(year, month, day, 0, 0, 0, 0);
    
    return {
      date: range.label,
      start: baseDate.toISOString(),
      end: baseDate.toISOString(),
      totalItems: totalsByLabel.get(range.label) ?? 0,
      itemsPacked: packedByLabel.get(range.label) ?? 0,
    };
  });
}

function normalizeDayLabel(label: string | Date | null, timeZone: string): string | null {
  if (!label) {
    return null;
  }
  if (label instanceof Date) {
    return formatDateInTimezone(label, timeZone);
  }
  if (typeof label === 'string') {
    return label.length === 10 && label.includes('-')
      ? label
      : formatDateInTimezone(new Date(label), timeZone);
  }
  return null;
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
          machineDescription: string;
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
    const locationTotal = toNumber(row.location_total);
    if (total <= 0) {
      continue;
    }

    if (!locations.has(row.location_id)) {
      locations.set(row.location_id, {
        locationId: row.location_id,
        locationName: row.location_name ?? 'Unknown location',
        totalItems: locationTotal > 0 ? locationTotal : 0,
        machines: new Map(),
      });
    }

    const locationEntry = locations.get(row.location_id)!;
    if (locationTotal > 0) {
      locationEntry.totalItems = locationTotal;
    } else {
      locationEntry.totalItems += total;
    }

    if (!locationEntry.machines.has(row.machine_id)) {
      locationEntry.machines.set(row.machine_id, {
        machineId: row.machine_id,
        machineCode: row.machine_code ?? 'Unknown',
        machineDescription: row.machine_description ?? row.machine_code ?? 'Unknown',
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
  if (typeof value === 'object' && value !== null) {
    if ('toNumber' in (value as Prisma.Decimal) && typeof (value as Prisma.Decimal).toNumber === 'function') {
      return (value as Prisma.Decimal).toNumber();
    }
    if ('valueOf' in (value as { valueOf: unknown })) {
      const raw = (value as { valueOf: () => unknown }).valueOf();
      const parsed = Number(raw);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

export const analyticsRouter = router;
