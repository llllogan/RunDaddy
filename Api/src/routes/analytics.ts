import { Router } from 'express';
import type { Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import {
  getTimezoneDayRange,
  isValidTimezone,
  formatDateInTimezone,
  convertDateToTimezoneMidnight,
} from '../lib/timezone.js';
import type { TimezoneDayRange } from '../lib/timezone.js';
import { AuthContext } from '../types/enums.js';
import { parseTimezoneQueryParam, resolveCompanyTimezone } from './helpers/timezone.js';
import { formatAppDate, formatAppExclusiveRange } from './helpers/app-dates.js';

const LOOKBACK_DEFAULT = 30;
const LOOKBACK_MIN = 7;
const LOOKBACK_MAX = 90;
const TOP_SKU_LOOKBACK_DEFAULT = 365;
const TOP_SKU_LOOKBACK_MIN = 30;
const TOP_SKU_LOOKBACK_MAX = 365;
const TOP_SKU_LIMIT_DEFAULT = 6;
const TOP_SKU_LIMIT_MIN = 3;
const TOP_SKU_LIMIT_MAX = 12;
const DAY_IN_MS = 24 * 60 * 60 * 1000;
const WEEK_IN_MS = 7 * DAY_IN_MS;
const MONTHS_IN_YEAR = 12;
const QUARTERS_IN_YEAR = 4;
const PERIOD_TYPES = ['week', 'month', 'quarter'] as const;
const SEARCH_SUGGESTION_LIMIT = 2;
const DASHBOARD_ANALYTICS_SKU_SEGMENT_LIMIT = 4;

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

type TopSkuRow = {
  sku_id: string | null;
  sku_code: string | null;
  sku_name: string | null;
  sku_type: string | null;
  total_picked: bigint | number | string | null;
};

type SkuLocationRow = {
  location_id: string | null;
  location_name: string | null;
  total_items: bigint | number | string | null;
};

type SkuMachineRow = {
  machine_id: string | null;
  machine_code: string | null;
  machine_description: string | null;
  location_id: string | null;
  location_name: string | null;
  total_items: bigint | number | string | null;
};

type SearchSuggestionLocationRow = {
  location_id: string | null;
  location_name: string | null;
  address: string | null;
  total_packed: bigint | number | string | null;
};

type SearchSuggestionMachineRow = {
  machine_id: string | null;
  machine_code: string | null;
  machine_description: string | null;
  location_id: string | null;
  location_name: string | null;
  total_packed: bigint | number | string | null;
};

type SearchSuggestionSkuRow = {
  sku_id: string | null;
  sku_code: string | null;
  sku_name: string | null;
  sku_type: string | null;
  category: string | null;
  total_packed: bigint | number | string | null;
};

type DashboardSkuMomentumRow = {
  sku_id: string | null;
  sku_code: string | null;
  sku_name: string | null;
  current_total: bigint | number | string | null;
  previous_total: bigint | number | string | null;
};

type DashboardMachineMomentumRow = {
  machine_id: string | null;
  machine_code: string | null;
  machine_description: string | null;
  location_id: string | null;
  location_name: string | null;
  current_total: bigint | number | string | null;
  previous_total: bigint | number | string | null;
};

type DashboardLocationMomentumRow = {
  location_id: string | null;
  location_name: string | null;
  current_total: bigint | number | string | null;
  previous_total: bigint | number | string | null;
};

type DashboardSkuComparisonRow = {
  sku_id: string | null;
  current_total: bigint | number | string | null;
  previous_total: bigint | number | string | null;
};

type DashboardSkuTotalsRow = {
  current_total: bigint | number | string | null;
  previous_total: bigint | number | string | null;
};

type DashboardAnalyticsSummary = {
  skuComparison: DashboardAnalyticsSkuComparison | null;
};

type DashboardAnalyticsSkuComparison = {
  totals: DashboardAnalyticsSkuTotals;
  segments: DashboardAnalyticsSkuComparisonSegment[];
};

type DashboardAnalyticsSkuTotals = {
  currentWeek: number;
  previousWeek: number;
};

type DashboardAnalyticsSkuComparisonSegment = {
  skuId: string;
  currentTotal: number;
  previousTotal: number;
  isOther: boolean;
};

type MomentumDirection = 'up' | 'down';

type MomentumLeaderRows<RowType> = {
  up: RowType | null;
  down: RowType | null;
};

type MomentumLeadersResponse<LeaderType> = {
  up: LeaderType | null;
  down: LeaderType | null;
  defaultSelection: MomentumDirection;
};

const router = Router();

router.use(authenticate);

router.get('/daily-totals', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildLookbackContext(req, res);
  if (!context) {
    return;
  }

  const dailyRows = await fetchDailyRows(context.companyId, context.lookbackDays, context.timeZone);
  const dayRangesWithTomorrow = appendTomorrowRange(context.dayRanges, context.timeZone, context.now);
  const points = buildDailySeries(dayRangesWithTomorrow, dailyRows);
  const responseRangeEnd =
    dayRangesWithTomorrow[dayRangesWithTomorrow.length - 1]?.end ?? context.rangeEnd;
  const responseRange = formatAppExclusiveRange(
    { start: context.rangeStart, end: responseRangeEnd },
    context.timeZone,
  );

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays: context.lookbackDays,
    rangeStart: responseRange.start,
    rangeEnd: responseRange.end,
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
  const responseRange = formatAppExclusiveRange(
    { start: context.rangeStart, end: context.rangeEnd },
    context.timeZone,
  );

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays: context.lookbackDays,
    rangeStart: responseRange.start,
    rangeEnd: responseRange.end,
    locations,
  });
});

router.get('/skus/top-picked', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildTimezoneContext(req, res);
  if (!context) {
    return;
  }

  const lookbackDays = parseTopSkuLookbackDays(req.query.lookbackDays);
  const limit = parseTopSkuLimit(req.query.limit);
  const locationFilter = normalizeFilterValue(req.query.locationId);
  const machineFilter = normalizeFilterValue(req.query.machineId);
  const { rangeStart, rangeEnd } = buildTopSkuRange(context.timeZone, context.now, lookbackDays);

  const [skuRows, locationRows, machineRows] = await Promise.all([
    fetchTopSkuRows(
      context.companyId,
      rangeStart,
      rangeEnd,
      limit,
      locationFilter,
      machineFilter,
    ),
    fetchSkuLocationRows(context.companyId, rangeStart, rangeEnd),
    fetchSkuMachineRows(context.companyId, rangeStart, rangeEnd),
  ]);

  const responseRange = formatAppExclusiveRange({ start: rangeStart, end: rangeEnd }, context.timeZone);

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays,
    rangeStart: responseRange.start,
    rangeEnd: responseRange.end,
    limit,
    appliedFilters: {
      locationId: locationFilter,
      machineId: machineFilter,
    },
    skus: skuRows
      .filter((row) => row.sku_id)
      .map((row) => ({
        skuId: row.sku_id!,
        skuCode: row.sku_code ?? 'SKU',
        skuName: row.sku_name ?? row.sku_code ?? 'SKU',
        skuType: row.sku_type ?? 'General',
        totalPicked: Math.max(toNumber(row.total_picked), 0),
      })),
    locations: locationRows
      .filter((row) => row.location_id)
      .map((row) => ({
        locationId: row.location_id!,
        locationName: row.location_name ?? 'Location',
        totalItems: Math.max(toNumber(row.total_items), 0),
      })),
    machines: machineRows
      .filter((row) => row.machine_id)
      .map((row) => ({
        machineId: row.machine_id!,
        machineCode: row.machine_code ?? 'Machine',
        machineDescription: row.machine_description ?? row.machine_code ?? 'Machine',
        locationId: row.location_id,
        locationName: row.location_name ?? undefined,
        totalItems: Math.max(toNumber(row.total_items), 0),
      })),
  });
});


router.get('/search', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildTimezoneContext(req, res);
  if (!context) {
    return;
  }

  const query = req.query.q as string;
  if (!query || query.trim().length === 0) {
    res.status(400).json({ error: 'Search query is required' });
    return;
  }

  const searchTerm = `%${query.trim()}%`;

  const [locations, machines, skus] = await Promise.all([
    prisma.$queryRaw<Array<{ id: string; name: string; address: string | null }>>(
      Prisma.sql`
        SELECT id, name, address
        FROM Location
        WHERE companyId = ${context.companyId}
          AND (name LIKE ${searchTerm} OR address LIKE ${searchTerm})
        ORDER BY name ASC
        LIMIT 10
      `,
    ),
    prisma.$queryRaw<Array<{ id: string; code: string; description: string | null }>>(
      Prisma.sql`
        SELECT id, code, description
        FROM Machine
        WHERE companyId = ${context.companyId}
          AND (code LIKE ${searchTerm} OR description LIKE ${searchTerm})
        ORDER BY code ASC
        LIMIT 10
      `,
    ),
    prisma.$queryRaw<Array<{ id: string; code: string; name: string; type: string; category: string | null }>>(
      Prisma.sql`
        SELECT id, code, name, type, category
        FROM SKU
        WHERE code LIKE ${searchTerm} 
           OR name LIKE ${searchTerm} 
           OR type LIKE ${searchTerm} 
           OR category LIKE ${searchTerm}
        ORDER BY code ASC
        LIMIT 10
      `,
    ),
  ]);

  const results = [
    ...locations.map(item => ({
      type: 'location',
      id: item.id,
      title: item.name,
      subtitle: item.address || 'No address',
    })),
    ...machines.map(item => ({
      type: 'machine',
      id: item.id,
      title: item.code,
      subtitle: item.description || 'No description',
    })),
    ...skus.map(item => {
      return {
        type: 'sku',
        id: item.id,
        title: item.code,
        subtitle: buildSkuSubtitle(item.name, item.type, item.category),
      };
    }),
  ];

  res.json({
    generatedAt: new Date().toISOString(),
    query: query.trim(),
    results,
  });
});

router.get('/search/suggestions', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildTimezoneContext(req, res);
  if (!context) {
    return;
  }

  const lookbackDays = parseTopSkuLookbackDays(req.query.lookbackDays);
  const { rangeStart, rangeEnd } = buildTopSkuRange(context.timeZone, context.now, lookbackDays);

  const [locations, machines, skus] = await Promise.all([
    fetchTopPackedLocations(context.companyId, rangeStart, rangeEnd, SEARCH_SUGGESTION_LIMIT),
    fetchTopPackedMachines(context.companyId, rangeStart, rangeEnd, SEARCH_SUGGESTION_LIMIT),
    fetchTopPackedSkus(context.companyId, rangeStart, rangeEnd, SEARCH_SUGGESTION_LIMIT),
  ]);

  const results = [
    ...locations
      .filter(row => row.location_id)
      .map(row => ({
        type: 'location',
        id: row.location_id!,
        title: row.location_name ?? 'Location',
        subtitle: row.address ?? 'No address',
      })),
    ...machines
      .filter(row => row.machine_id)
      .map(row => ({
        type: 'machine',
        id: row.machine_id!,
        title: row.machine_code ?? 'Machine',
        subtitle: row.machine_description ?? 'No description',
      })),
    ...skus
      .filter(row => row.sku_id)
      .map(row => ({
        type: 'sku',
        id: row.sku_id!,
        title: row.sku_code ?? 'SKU',
        subtitle: buildSkuSubtitle(row.sku_name, row.sku_type, row.category),
      })),
  ];

  res.json({
    generatedAt: new Date().toISOString(),
    query: '',
    results,
  });
});

router.get('/packs/period-comparison', setLogConfig({ level: 'full' }), async (req, res) => {
  const context = await buildTimezoneContext(req, res);
  if (!context) {
    return;
  }

  const periodComparisons = await Promise.all(
    PERIOD_TYPES.map((period) => buildPeriodComparison(period, context)),
  );

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    periods: periodComparisons,
  });
});

router.get('/dashboard', setLogConfig({ level: 'full' }), async (req, res) => {
  const context = await buildTimezoneContext(req, res);
  if (!context) {
    return;
  }

  const weekWindow = buildDashboardWeekWindow(context.timeZone, context.now);
  const [
    skuLeaderRows,
    machineLeaderRows,
    locationLeaderRows,
    skuComparisonSegmentRows,
    skuComparisonTotalsRow,
  ] = await Promise.all([
    fetchDashboardSkuMomentumRows(context.companyId, weekWindow),
    fetchDashboardMachineMomentumRows(context.companyId, weekWindow),
    fetchDashboardLocationMomentumRows(context.companyId, weekWindow),
    fetchDashboardSkuComparisonSegments(
      context.companyId,
      weekWindow,
      DASHBOARD_ANALYTICS_SKU_SEGMENT_LIMIT,
    ),
    fetchDashboardSkuComparisonTotals(context.companyId, weekWindow),
  ]);

  const analyticsSummary = buildDashboardAnalyticsSummary(
    skuComparisonSegmentRows,
    skuComparisonTotalsRow,
  );
  const currentWeekRange = formatAppExclusiveRange(
    { start: weekWindow.currentStart, end: weekWindow.currentEnd },
    context.timeZone,
  );
  const previousWeekRange = formatAppExclusiveRange(
    { start: weekWindow.previousStart, end: weekWindow.previousEnd },
    context.timeZone,
  );

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    currentWeek: {
      start: currentWeekRange.start,
      end: currentWeekRange.end,
      comparisonEnd: formatAppDate(weekWindow.currentComparisonEnd, context.timeZone),
      progressPercentage: Number((weekWindow.progressFraction * 100).toFixed(2)),
    },
    previousWeek: {
      start: previousWeekRange.start,
      end: previousWeekRange.end,
      comparisonEnd: formatAppDate(weekWindow.previousComparisonEnd, context.timeZone),
    },
    leaders: {
      sku: buildMomentumLeaderResponse(skuLeaderRows, mapSkuMomentumLeader),
      machine: buildMomentumLeaderResponse(machineLeaderRows, mapMachineMomentumLeader),
      location: buildMomentumLeaderResponse(locationLeaderRows, mapLocationMomentumLeader),
    },
    analytics: analyticsSummary,
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

type PeriodType = (typeof PERIOD_TYPES)[number];

type PeriodWindow = {
  start: Date;
  end: Date;
};

type PeriodComparison = {
  period: PeriodType;
  progressPercentage: number;
  comparisonDurationMs: number;
  currentPeriod: {
    start: string;
    end: string;
    comparisonEnd: string;
    totalItems: number;
  };
  previousPeriods: Array<{
    index: number;
    start: string;
    end: string;
    comparisonEnd: string;
    totalItems: number;
  }>;
  averages: {
    previousAverage: number | null;
    deltaFromPreviousAverage: number | null;
    deltaPercentage: number | null;
  };
};

type DashboardWeekWindow = {
  currentStart: Date;
  currentEnd: Date;
  currentComparisonEnd: Date;
  previousStart: Date;
  previousEnd: Date;
  previousComparisonEnd: Date;
  progressFraction: number;
  comparisonDurationMs: number;
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
  const persistTimezone = req.auth.context === AuthContext.APP;
  const timeZone = await resolveCompanyTimezone(req.auth.companyId, timezoneOverride, {
    persistIfMissing: persistTimezone,
  });

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

function parseTopSkuLookbackDays(value: unknown): number {
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return clamp(parsed, TOP_SKU_LOOKBACK_MIN, TOP_SKU_LOOKBACK_MAX);
    }
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return clamp(Math.trunc(value), TOP_SKU_LOOKBACK_MIN, TOP_SKU_LOOKBACK_MAX);
  }
  return TOP_SKU_LOOKBACK_DEFAULT;
}

function parseTopSkuLimit(value: unknown): number {
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return clamp(parsed, TOP_SKU_LIMIT_MIN, TOP_SKU_LIMIT_MAX);
    }
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return clamp(Math.trunc(value), TOP_SKU_LIMIT_MIN, TOP_SKU_LIMIT_MAX);
  }
  return TOP_SKU_LIMIT_DEFAULT;
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

async function fetchTopSkuRows(
  companyId: string,
  rangeStart: Date,
  rangeEnd: Date,
  limit: number,
  locationId: string | null,
  machineId: string | null,
) {
  const locationFilter = locationId ? Prisma.sql`AND loc.id = ${locationId}` : Prisma.sql``;
  const machineFilter = machineId ? Prisma.sql`AND mach.id = ${machineId}` : Prisma.sql``;

  return prisma.$queryRaw<TopSkuRow[]>(
    Prisma.sql`
      SELECT
        sku.id AS sku_id,
        sku.code AS sku_code,
        sku.name AS sku_name,
        sku.type AS sku_type,
        SUM(pe.count) AS total_picked
      FROM PickEntry pe
      JOIN Run r ON r.id = pe.runId
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN SKU sku ON sku.id = ci.skuId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      LEFT JOIN Location loc ON loc.id = mach.locationId
      WHERE r.companyId = ${companyId}
        AND r.scheduledFor IS NOT NULL
        AND r.scheduledFor >= ${rangeStart}
        AND r.scheduledFor < ${rangeEnd}
        ${locationFilter}
        ${machineFilter}
      GROUP BY sku.id, sku.code, sku.name, sku.type
      HAVING SUM(pe.count) > 0
      ORDER BY total_picked DESC
      LIMIT ${Prisma.raw(String(limit))}
    `,
  );
}

async function fetchSkuLocationRows(companyId: string, rangeStart: Date, rangeEnd: Date) {
  return prisma.$queryRaw<SkuLocationRow[]>(
    Prisma.sql`
      WITH location_totals AS (
        SELECT
          loc.id AS location_id,
          SUM(pe.count) AS total_items
        FROM PickEntry pe
        JOIN Run r ON r.id = pe.runId
        JOIN CoilItem ci ON ci.id = pe.coilItemId
        JOIN Coil coil ON coil.id = ci.coilId
        JOIN Machine mach ON mach.id = coil.machineId
        LEFT JOIN Location loc ON loc.id = mach.locationId
        WHERE r.companyId = ${companyId}
          AND r.scheduledFor IS NOT NULL
          AND r.scheduledFor >= ${rangeStart}
          AND r.scheduledFor < ${rangeEnd}
          AND loc.id IS NOT NULL
        GROUP BY loc.id
      )
      SELECT
        loc.id AS location_id,
        loc.name AS location_name,
        COALESCE(lt.total_items, 0) AS total_items
      FROM Location loc
      LEFT JOIN location_totals lt ON lt.location_id = loc.id
      WHERE loc.companyId = ${companyId}
      ORDER BY loc.name ASC
    `,
  );
}

async function fetchSkuMachineRows(companyId: string, rangeStart: Date, rangeEnd: Date) {
  return prisma.$queryRaw<SkuMachineRow[]>(
    Prisma.sql`
      WITH machine_totals AS (
        SELECT
          mach.id AS machine_id,
          SUM(pe.count) AS total_items
        FROM PickEntry pe
        JOIN Run r ON r.id = pe.runId
        JOIN CoilItem ci ON ci.id = pe.coilItemId
        JOIN Coil coil ON coil.id = ci.coilId
        JOIN Machine mach ON mach.id = coil.machineId
        WHERE r.companyId = ${companyId}
          AND r.scheduledFor IS NOT NULL
          AND r.scheduledFor >= ${rangeStart}
          AND r.scheduledFor < ${rangeEnd}
        GROUP BY mach.id
      )
      SELECT
        mach.id AS machine_id,
        mach.code AS machine_code,
        mach.description AS machine_description,
        loc.id AS location_id,
        loc.name AS location_name,
        COALESCE(mt.total_items, 0) AS total_items
      FROM Machine mach
      LEFT JOIN machine_totals mt ON mt.machine_id = mach.id
      LEFT JOIN Location loc ON loc.id = mach.locationId
      WHERE mach.companyId = ${companyId}
      ORDER BY mach.code ASC
    `,
  );
}

async function fetchTopPackedLocations(
  companyId: string,
  rangeStart: Date,
  rangeEnd: Date,
  limit: number,
) {
  return prisma.$queryRaw<SearchSuggestionLocationRow[]>(
    Prisma.sql`
      SELECT
        loc.id AS location_id,
        loc.name AS location_name,
        loc.address AS address,
        SUM(pe.count) AS total_packed
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
      GROUP BY loc.id, loc.name, loc.address
      HAVING SUM(pe.count) > 0
      ORDER BY total_packed DESC, loc.name ASC
      LIMIT ${Prisma.raw(String(limit))}
    `,
  );
}

async function fetchTopPackedMachines(
  companyId: string,
  rangeStart: Date,
  rangeEnd: Date,
  limit: number,
) {
  return prisma.$queryRaw<SearchSuggestionMachineRow[]>(
    Prisma.sql`
      SELECT
        mach.id AS machine_id,
        mach.code AS machine_code,
        mach.description AS machine_description,
        loc.id AS location_id,
        loc.name AS location_name,
        SUM(pe.count) AS total_packed
      FROM PickEntry pe
      JOIN Run r ON r.id = pe.runId
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      LEFT JOIN Location loc ON loc.id = mach.locationId
      WHERE r.companyId = ${companyId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND pe.pickedAt >= ${rangeStart}
        AND pe.pickedAt < ${rangeEnd}
      GROUP BY mach.id, mach.code, mach.description, loc.id, loc.name
      HAVING SUM(pe.count) > 0
      ORDER BY total_packed DESC, mach.code ASC
      LIMIT ${Prisma.raw(String(limit))}
    `,
  );
}

async function fetchTopPackedSkus(
  companyId: string,
  rangeStart: Date,
  rangeEnd: Date,
  limit: number,
) {
  return prisma.$queryRaw<SearchSuggestionSkuRow[]>(
    Prisma.sql`
      SELECT
        sku.id AS sku_id,
        sku.code AS sku_code,
        sku.name AS sku_name,
        sku.type AS sku_type,
        sku.category AS category,
        SUM(pe.count) AS total_packed
      FROM PickEntry pe
      JOIN Run r ON r.id = pe.runId
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN SKU sku ON sku.id = ci.skuId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      WHERE r.companyId = ${companyId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND pe.pickedAt >= ${rangeStart}
        AND pe.pickedAt < ${rangeEnd}
      GROUP BY sku.id, sku.code, sku.name, sku.type, sku.category
      HAVING SUM(pe.count) > 0
      ORDER BY total_packed DESC, sku.code ASC
      LIMIT ${Prisma.raw(String(limit))}
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
    return {
      date: range.label,
      start: range.label,
      end: range.label,
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

function buildSkuSubtitle(name: string | null, type: string | null, category: string | null): string {
  const subtitleParts: string[] = [];
  if (name) {
    subtitleParts.push(name);
  }
  const trimmedType = (type ?? '').trim();
  if (trimmedType) {
    const normalizedType = trimmedType.toLowerCase();
    if (normalizedType !== 'general') {
      subtitleParts.push(trimmedType);
    }
  }
  if (category) {
    subtitleParts.push(category);
  }
  return subtitleParts.length > 0 ? subtitleParts.join(' • ') : 'SKU';
}

async function sumPackedItems(companyId: string, rangeStart: Date, rangeEnd: Date): Promise<number> {
  const [row] = await prisma.$queryRaw<{ total_items: bigint | number | string | null }[]>(
    Prisma.sql`
      SELECT COALESCE(SUM(pe.count), 0) AS total_items
      FROM PickEntry pe
      JOIN Run r ON r.id = pe.runId
      WHERE r.companyId = ${companyId}
        AND r.scheduledFor IS NOT NULL
        AND r.scheduledFor >= ${rangeStart}
        AND r.scheduledFor < ${rangeEnd}
    `,
  );

  return toNumber(row?.total_items ?? 0);
}

async function buildPeriodComparison(period: PeriodType, context: TimezoneContext): Promise<PeriodComparison> {
  const currentWindow = getPeriodWindow(period, context.timeZone, context.now, 0);
  const durationMs = Math.max(currentWindow.end.getTime() - currentWindow.start.getTime(), 0);
  const elapsedMs = Math.min(
    Math.max(context.now.getTime() - currentWindow.start.getTime(), 0),
    durationMs,
  );
  const progressFraction = durationMs > 0 ? elapsedMs / durationMs : 0;
  const currentComparisonEnd = currentWindow.end;

  const currentTotalPromise = sumPackedItems(
    context.companyId,
    currentWindow.start,
    currentComparisonEnd,
  );

  // Fetch totals for the three prior full periods for comparison.
  const previousPeriods = await Promise.all(
    [1, 2, 3].map(async (index) => {
      const window = getPeriodWindow(period, context.timeZone, context.now, index);
      const totalItems = await sumPackedItems(context.companyId, window.start, window.end);
      const range = formatAppExclusiveRange(
        { start: window.start, end: window.end },
        context.timeZone,
      );
      return {
        index,
        start: range.start,
        end: range.end,
        comparisonEnd: range.end,
        totalItems,
      };
    }),
  );

  const currentTotal = await currentTotalPromise;
  const previousTotals = previousPeriods.map((entry) => entry.totalItems);
  const previousAverageRaw =
    previousTotals.length > 0
      ? previousTotals.reduce((sum, value) => sum + value, 0) / previousTotals.length
      : null;
  const previousAverage =
    previousAverageRaw !== null ? Number(previousAverageRaw.toFixed(2)) : null;
  const deltaFromPreviousAverage =
    previousAverageRaw !== null ? Number((currentTotal - previousAverageRaw).toFixed(2)) : null;
  const deltaPercentage =
    previousAverageRaw && previousAverageRaw !== 0
      ? Number((((currentTotal - previousAverageRaw) / previousAverageRaw) * 100).toFixed(2))
      : null;

  const currentRange = formatAppExclusiveRange(
    { start: currentWindow.start, end: currentWindow.end },
    context.timeZone,
  );

  return {
    period,
    progressPercentage: Number((progressFraction * 100).toFixed(2)),
    comparisonDurationMs: durationMs,
    currentPeriod: {
      start: currentRange.start,
      end: currentRange.end,
      comparisonEnd: currentRange.end,
      totalItems: currentTotal,
    },
    previousPeriods,
    averages: {
      previousAverage,
      deltaFromPreviousAverage,
      deltaPercentage,
    },
  };
}

function getPeriodWindow(
  period: PeriodType,
  timeZone: string,
  reference: Date,
  offset: number,
): PeriodWindow {
  if (period === 'week') {
    const currentWeekStart = getIsoWeekStart(timeZone, reference);
    const start = new Date(currentWeekStart.getTime() - offset * WEEK_IN_MS);
    return {
      start,
      end: new Date(start.getTime() + WEEK_IN_MS),
    };
  }
  if (period === 'month') {
    return getMonthWindow(timeZone, reference, offset);
  }
  return getQuarterWindow(timeZone, reference, offset);
}

function getMonthWindow(timeZone: string, reference: Date, offset: number): PeriodWindow {
  const { year, month } = getLocalDatePartsInTimezone(reference, timeZone);
  const absoluteMonth = year * MONTHS_IN_YEAR + (month - 1) - offset;
  const startYear = Math.floor(absoluteMonth / MONTHS_IN_YEAR);
  const startMonthIndex = mod(absoluteMonth, MONTHS_IN_YEAR);

  const startBase = new Date(Date.UTC(startYear, startMonthIndex, 1, 0, 0, 0, 0));
  const endBase = new Date(Date.UTC(startYear, startMonthIndex + 1, 1, 0, 0, 0, 0));
  return {
    start: convertDateToTimezoneMidnight(startBase, timeZone),
    end: convertDateToTimezoneMidnight(endBase, timeZone),
  };
}

function getQuarterWindow(timeZone: string, reference: Date, offset: number): PeriodWindow {
  const { year, month } = getLocalDatePartsInTimezone(reference, timeZone);
  const currentQuarterIndex = Math.floor((month - 1) / 3);
  const absoluteQuarter = year * QUARTERS_IN_YEAR + currentQuarterIndex - offset;
  const startYear = Math.floor(absoluteQuarter / QUARTERS_IN_YEAR);
  const startQuarterIndex = mod(absoluteQuarter, QUARTERS_IN_YEAR);
  const startMonthIndex = startQuarterIndex * 3;

  const startBase = new Date(Date.UTC(startYear, startMonthIndex, 1, 0, 0, 0, 0));
  const endBase = new Date(Date.UTC(startYear, startMonthIndex + 3, 1, 0, 0, 0, 0));
  return {
    start: convertDateToTimezoneMidnight(startBase, timeZone),
    end: convertDateToTimezoneMidnight(endBase, timeZone),
  };
}

function getLocalDatePartsInTimezone(reference: Date, timeZone: string) {
  const label = formatDateInTimezone(reference, timeZone);
  const [yearRaw, monthRaw, dayRaw] = label.split('-');
  return {
    year: Number.parseInt(yearRaw ?? '0', 10),
    month: Number.parseInt(monthRaw ?? '1', 10),
    day: Number.parseInt(dayRaw ?? '1', 10),
  };
}

function mod(value: number, divisor: number): number {
  const remainder = value % divisor;
  return remainder < 0 ? remainder + divisor : remainder;
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

function normalizeFilterValue(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function buildTopSkuRange(timeZone: string, reference: Date, lookbackDays: number) {
  const inclusiveEndReference = new Date(reference.getTime() + DAY_IN_MS);
  const rangeEnd = convertDateToTimezoneMidnight(inclusiveEndReference, timeZone);
  const startSeed = new Date(rangeEnd.getTime() - lookbackDays * DAY_IN_MS);
  const rangeStart = convertDateToTimezoneMidnight(startSeed, timeZone);
  return { rangeStart, rangeEnd };
}

function buildDashboardWeekWindow(timeZone: string, reference: Date): DashboardWeekWindow {
  const currentStart = getIsoWeekStart(timeZone, reference);
  const currentEnd = new Date(currentStart.getTime() + WEEK_IN_MS);
  const startMs = currentStart.getTime();
  const endMs = currentEnd.getTime();
  const clampedNowMs = clamp(reference.getTime(), startMs, endMs);
  const comparisonDurationMs = Math.max(0, Math.min(WEEK_IN_MS, clampedNowMs - startMs));
  const previousStart = new Date(currentStart.getTime() - WEEK_IN_MS);
  const previousEnd = new Date(currentStart);

  return {
    currentStart,
    currentEnd,
    currentComparisonEnd: new Date(startMs + comparisonDurationMs),
    previousStart,
    previousEnd,
    previousComparisonEnd: new Date(previousStart.getTime() + comparisonDurationMs),
    progressFraction: WEEK_IN_MS === 0 ? 0 : comparisonDurationMs / WEEK_IN_MS,
    comparisonDurationMs,
  };
}

async function fetchDashboardSkuMomentumRows(companyId: string, window: DashboardWeekWindow) {
  const [up, down] = await Promise.all([
    fetchDashboardSkuMomentumLeader(companyId, window, 'desc'),
    fetchDashboardSkuMomentumLeader(companyId, window, 'asc'),
  ]);
  return { up, down } satisfies MomentumLeaderRows<DashboardSkuMomentumRow>;
}

async function fetchDashboardSkuMomentumLeader(
  companyId: string,
  window: DashboardWeekWindow,
  direction: 'asc' | 'desc' = 'desc',
) {
  const orderDirection = direction === 'desc' ? Prisma.sql`DESC` : Prisma.sql`ASC`;
  const rows = await prisma.$queryRaw<DashboardSkuMomentumRow[]>(
    Prisma.sql`
      SELECT *
      FROM (
        SELECT
          sku.id AS sku_id,
          sku.code AS sku_code,
          sku.name AS sku_name,
          SUM(CASE 
                WHEN r.scheduledFor >= ${window.currentStart}
                 AND r.scheduledFor < ${window.currentComparisonEnd}
                THEN pe.count
                ELSE 0
              END) AS current_total,
          SUM(CASE 
                WHEN r.scheduledFor >= ${window.previousStart}
                 AND r.scheduledFor < ${window.previousComparisonEnd}
                THEN pe.count
                ELSE 0
              END) AS previous_total
        FROM PickEntry pe
        JOIN Run r ON r.id = pe.runId
        JOIN CoilItem ci ON ci.id = pe.coilItemId
        JOIN SKU sku ON sku.id = ci.skuId
        WHERE r.companyId = ${companyId}
          AND r.scheduledFor IS NOT NULL
          AND r.scheduledFor >= ${window.previousStart}
          AND r.scheduledFor < ${window.currentComparisonEnd}
        GROUP BY sku.id, sku.code, sku.name
      ) AS sku_totals
      WHERE current_total > 0 OR previous_total > 0
      ORDER BY (current_total - previous_total) ${orderDirection}, current_total DESC
      LIMIT 1
    `,
  );
  return rows[0] ?? null;
}

async function fetchDashboardMachineMomentumRows(companyId: string, window: DashboardWeekWindow) {
  const [up, down] = await Promise.all([
    fetchDashboardMachineMomentumLeader(companyId, window, 'desc'),
    fetchDashboardMachineMomentumLeader(companyId, window, 'asc'),
  ]);
  return { up, down } satisfies MomentumLeaderRows<DashboardMachineMomentumRow>;
}

async function fetchDashboardMachineMomentumLeader(
  companyId: string,
  window: DashboardWeekWindow,
  direction: 'asc' | 'desc' = 'desc',
) {
  const orderDirection = direction === 'desc' ? Prisma.sql`DESC` : Prisma.sql`ASC`;
  const rows = await prisma.$queryRaw<DashboardMachineMomentumRow[]>(
    Prisma.sql`
      SELECT *
      FROM (
        SELECT
          mach.id AS machine_id,
          mach.code AS machine_code,
          mach.description AS machine_description,
          loc.id AS location_id,
          loc.name AS location_name,
          SUM(CASE 
                WHEN r.scheduledFor >= ${window.currentStart}
                 AND r.scheduledFor < ${window.currentComparisonEnd}
                THEN pe.count
                ELSE 0
              END) AS current_total,
          SUM(CASE 
                WHEN r.scheduledFor >= ${window.previousStart}
                 AND r.scheduledFor < ${window.previousComparisonEnd}
                THEN pe.count
                ELSE 0
              END) AS previous_total
        FROM PickEntry pe
        JOIN Run r ON r.id = pe.runId
        JOIN CoilItem ci ON ci.id = pe.coilItemId
        JOIN Coil coil ON coil.id = ci.coilId
        JOIN Machine mach ON mach.id = coil.machineId
        LEFT JOIN Location loc ON loc.id = mach.locationId
        WHERE r.companyId = ${companyId}
          AND r.scheduledFor IS NOT NULL
          AND r.scheduledFor >= ${window.previousStart}
          AND r.scheduledFor < ${window.currentComparisonEnd}
        GROUP BY mach.id, mach.code, mach.description, loc.id, loc.name
      ) AS machine_totals
      WHERE current_total > 0 OR previous_total > 0
      ORDER BY (current_total - previous_total) ${orderDirection}, current_total DESC
      LIMIT 1
    `,
  );
  return rows[0] ?? null;
}

async function fetchDashboardLocationMomentumRows(
  companyId: string,
  window: DashboardWeekWindow,
) {
  const [up, down] = await Promise.all([
    fetchDashboardLocationMomentumLeader(companyId, window, 'desc'),
    fetchDashboardLocationMomentumLeader(companyId, window, 'asc'),
  ]);
  return { up, down } satisfies MomentumLeaderRows<DashboardLocationMomentumRow>;
}

async function fetchDashboardLocationMomentumLeader(
  companyId: string,
  window: DashboardWeekWindow,
  direction: 'asc' | 'desc' = 'desc',
) {
  const orderDirection = direction === 'desc' ? Prisma.sql`DESC` : Prisma.sql`ASC`;
  const rows = await prisma.$queryRaw<DashboardLocationMomentumRow[]>(
    Prisma.sql`
      SELECT *
      FROM (
        SELECT
          loc.id AS location_id,
          loc.name AS location_name,
          SUM(CASE 
                WHEN r.scheduledFor >= ${window.currentStart}
                 AND r.scheduledFor < ${window.currentComparisonEnd}
                THEN pe.count
                ELSE 0
              END) AS current_total,
          SUM(CASE 
                WHEN r.scheduledFor >= ${window.previousStart}
                 AND r.scheduledFor < ${window.previousComparisonEnd}
                THEN pe.count
                ELSE 0
              END) AS previous_total
        FROM PickEntry pe
        JOIN Run r ON r.id = pe.runId
        JOIN CoilItem ci ON ci.id = pe.coilItemId
        JOIN Coil coil ON coil.id = ci.coilId
        JOIN Machine mach ON mach.id = coil.machineId
        JOIN Location loc ON loc.id = mach.locationId
        WHERE r.companyId = ${companyId}
          AND r.scheduledFor IS NOT NULL
          AND r.scheduledFor >= ${window.previousStart}
          AND r.scheduledFor < ${window.currentComparisonEnd}
        GROUP BY loc.id, loc.name
      ) AS location_totals
      WHERE (current_total > 0 OR previous_total > 0) AND location_id IS NOT NULL
      ORDER BY (current_total - previous_total) ${orderDirection}, current_total DESC
      LIMIT 1
    `,
  );
  return rows[0] ?? null;
}

async function fetchDashboardSkuComparisonSegments(
  companyId: string,
  window: DashboardWeekWindow,
  limit: number = DASHBOARD_ANALYTICS_SKU_SEGMENT_LIMIT,
) {
  const safeLimit = Math.max(1, limit);
  return prisma.$queryRaw<DashboardSkuComparisonRow[]>(
    Prisma.sql`
      SELECT *
      FROM (
        SELECT
          ci.skuId AS sku_id,
          SUM(CASE 
                WHEN r.scheduledFor >= ${window.currentStart}
                 AND r.scheduledFor < ${window.currentComparisonEnd}
                THEN pe.count
                ELSE 0
              END) AS current_total,
          SUM(CASE 
                WHEN r.scheduledFor >= ${window.previousStart}
                 AND r.scheduledFor < ${window.previousComparisonEnd}
                THEN pe.count
                ELSE 0
              END) AS previous_total
        FROM PickEntry pe
        JOIN Run r ON r.id = pe.runId
        JOIN CoilItem ci ON ci.id = pe.coilItemId
        WHERE r.companyId = ${companyId}
          AND r.scheduledFor IS NOT NULL
          AND r.scheduledFor >= ${window.previousStart}
          AND r.scheduledFor < ${window.currentComparisonEnd}
          AND ci.skuId IS NOT NULL
        GROUP BY ci.skuId
      ) AS sku_totals
      WHERE current_total > 0 OR previous_total > 0
      ORDER BY (current_total + previous_total) DESC, current_total DESC, sku_id ASC
      LIMIT ${safeLimit}
    `,
  );
}

async function fetchDashboardSkuComparisonTotals(
  companyId: string,
  window: DashboardWeekWindow,
) {
  const rows = await prisma.$queryRaw<DashboardSkuTotalsRow[]>(
    Prisma.sql`
      SELECT
        SUM(CASE 
              WHEN r.scheduledFor >= ${window.currentStart}
               AND r.scheduledFor < ${window.currentComparisonEnd}
              THEN pe.count
              ELSE 0
            END) AS current_total,
        SUM(CASE 
              WHEN r.scheduledFor >= ${window.previousStart}
               AND r.scheduledFor < ${window.previousComparisonEnd}
              THEN pe.count
              ELSE 0
            END) AS previous_total
      FROM PickEntry pe
      JOIN Run r ON r.id = pe.runId
      WHERE r.companyId = ${companyId}
        AND r.scheduledFor IS NOT NULL
        AND r.scheduledFor >= ${window.previousStart}
        AND r.scheduledFor < ${window.currentComparisonEnd}
    `,
  );
  return rows[0] ?? null;
}

function mapSkuMomentumLeader(row: DashboardSkuMomentumRow | null) {
  if (!row || !row.sku_id) {
    return null;
  }
  const currentTotal = Math.max(toNumber(row.current_total), 0);
  const previousTotal = Math.max(toNumber(row.previous_total), 0);
  return {
    skuId: row.sku_id,
    skuCode: row.sku_code ?? 'SKU',
    skuName: row.sku_name ?? row.sku_code ?? 'SKU',
    currentTotal,
    previousTotal,
    delta: currentTotal - previousTotal,
  };
}

function mapMachineMomentumLeader(row: DashboardMachineMomentumRow | null) {
  if (!row || !row.machine_id) {
    return null;
  }
  const currentTotal = Math.max(toNumber(row.current_total), 0);
  const previousTotal = Math.max(toNumber(row.previous_total), 0);
  return {
    machineId: row.machine_id,
    machineCode: row.machine_code ?? 'Machine',
    machineDescription: row.machine_description ?? row.machine_code ?? 'Machine',
    locationId: row.location_id,
    locationName: row.location_name ?? undefined,
    currentTotal,
    previousTotal,
    delta: currentTotal - previousTotal,
  };
}

function mapLocationMomentumLeader(row: DashboardLocationMomentumRow | null) {
  if (!row || !row.location_id) {
    return null;
  }
  const currentTotal = Math.max(toNumber(row.current_total), 0);
  const previousTotal = Math.max(toNumber(row.previous_total), 0);
  return {
    locationId: row.location_id,
    locationName: row.location_name ?? 'Location',
    currentTotal,
    previousTotal,
    delta: currentTotal - previousTotal,
  };
}

function buildDashboardAnalyticsSummary(
  segmentRows: DashboardSkuComparisonRow[],
  totalsRow: DashboardSkuTotalsRow | null,
): DashboardAnalyticsSummary {
  return {
    skuComparison: buildDashboardSkuComparison(segmentRows, totalsRow),
  } satisfies DashboardAnalyticsSummary;
}

function buildDashboardSkuComparison(
  segmentRows: DashboardSkuComparisonRow[],
  totalsRow: DashboardSkuTotalsRow | null,
): DashboardAnalyticsSkuComparison | null {
  const totals = mapDashboardSkuTotals(totalsRow);
  const mappedSegments = segmentRows
    .map(mapDashboardSkuComparisonSegment)
    .filter((segment) => segment.currentTotal > 0 || segment.previousTotal > 0);

  let segments: DashboardAnalyticsSkuComparisonSegment[] = [...mappedSegments];
  const displayedCurrent = segments.reduce((sum, segment) => sum + segment.currentTotal, 0);
  const displayedPrevious = segments.reduce((sum, segment) => sum + segment.previousTotal, 0);
  const remainingCurrent = Math.max(totals.currentWeek - displayedCurrent, 0);
  const remainingPrevious = Math.max(totals.previousWeek - displayedPrevious, 0);

  if (remainingCurrent > 0 || remainingPrevious > 0) {
    segments = segments.concat({
      skuId: 'other',
      currentTotal: remainingCurrent,
      previousTotal: remainingPrevious,
      isOther: true,
    });
  }

  if (segments.length === 0) {
    return null;
  }

  return {
    totals,
    segments,
  } satisfies DashboardAnalyticsSkuComparison;
}

function mapDashboardSkuComparisonSegment(
  row: DashboardSkuComparisonRow,
): DashboardAnalyticsSkuComparisonSegment {
  const skuId = row.sku_id ?? '';
  const currentTotal = Math.max(toNumber(row.current_total), 0);
  const previousTotal = Math.max(toNumber(row.previous_total), 0);
  return {
    skuId,
    currentTotal,
    previousTotal,
    isOther: false,
  } satisfies DashboardAnalyticsSkuComparisonSegment;
}

function mapDashboardSkuTotals(row: DashboardSkuTotalsRow | null): DashboardAnalyticsSkuTotals {
  if (!row) {
    return {
      currentWeek: 0,
      previousWeek: 0,
    } satisfies DashboardAnalyticsSkuTotals;
  }

  return {
    currentWeek: Math.max(toNumber(row.current_total), 0),
    previousWeek: Math.max(toNumber(row.previous_total), 0),
  } satisfies DashboardAnalyticsSkuTotals;
}

function buildMomentumLeaderResponse<RowType, LeaderType extends { delta: number }>(
  rows: MomentumLeaderRows<RowType>,
  mapper: (row: RowType | null) => LeaderType | null,
): MomentumLeadersResponse<LeaderType> {
  const upLeader = sanitizeMomentumLeader(mapper(rows.up), 'up');
  const downLeader = sanitizeMomentumLeader(mapper(rows.down), 'down');

  return {
    up: upLeader,
    down: downLeader,
    defaultSelection: determineDefaultSelection(upLeader, downLeader),
  };
}

function sanitizeMomentumLeader<T extends { delta: number }>(
  leader: T | null,
  direction: MomentumDirection,
): T | null {
  if (!leader) {
    return null;
  }
  if (direction === 'up' && leader.delta < 0) {
    return null;
  }
  if (direction === 'down' && leader.delta >= 0) {
    return null;
  }
  return leader;
}

function determineDefaultSelection<T extends { delta: number }>(
  up: T | null,
  down: T | null,
): MomentumDirection {
  if (up && down) {
    const upMagnitude = Math.abs(up.delta);
    const downMagnitude = Math.abs(down.delta);
    if (downMagnitude > upMagnitude) {
      return 'down';
    }
    return 'up';
  }
  if (down) {
    return 'down';
  }
  return 'up';
}

export const analyticsRouter = router;
