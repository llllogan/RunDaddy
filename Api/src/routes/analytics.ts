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
import { resolveCompanyTimezone } from './helpers/timezone.js';
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
const MACHINE_PICK_LOOKBACK_DEFAULT = 14;
const DASHBOARD_MACHINE_TOUCH_WEEKS = 6;
const DAY_IN_MS = 24 * 60 * 60 * 1000;
const WEEK_IN_MS = 7 * DAY_IN_MS;
const MONTHS_IN_YEAR = 12;
const QUARTERS_IN_YEAR = 4;
const PERIOD_TYPES = ['week', 'month', 'quarter'] as const;
const SEARCH_SUGGESTION_LIMIT = 2;


const PICK_ENTRY_AGGREGATIONS = ['week', 'month', 'quarter'] as const;
const PICK_ENTRY_DEFAULT_PERIODS = 4;
const PICK_ENTRY_PERIOD_MIN = 1;
const PICK_ENTRY_PERIOD_MAX = 12;
const PICK_ENTRY_LOOKBACK_MAX = 180;
const PICK_ENTRY_BREAKDOWN_SHOW_BARS = {
  week: 8,
  month: 6,
  quarter: 4,
} as const;
const PICK_ENTRY_BREAKDOWN_MAX_BARS = 30;

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

type DailySkuRow = {
  day_label: string | Date | null;
  sku_id: string | null;
  sku_code: string | null;
  sku_name: string | null;
  total_items: bigint | number | string | null;
};

type DailyTotalRow = {
  day_label: string | Date | null;
  total_items: bigint | number | string | null;
};

type PickEntryBreakdownRow = {
  day_label: string | Date | null;
  sku_id: string | null;
  sku_code: string | null;
  sku_name: string | null;
  machine_id: string | null;
  machine_code: string | null;
  machine_description: string | null;
  location_id: string | null;
  location_name: string | null;
  total_items: bigint | number | string | null;
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

type MachinePickTotalRow = {
  machine_id: string | null;
  machine_code: string | null;
  machine_description: string | null;
  total_items: bigint | number | string | null;
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
};

type DashboardMachineTouchPoint = {
  weekStart: string;
  weekEnd: string;
  totalMachines: number;
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

router.get('/pick-entries/sku-breakdown', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildAggregatedLookbackContext(req, res);
  if (!context) {
    return;
  }

  const dayRangesWithTomorrow = appendTomorrowRange(context.dayRanges, context.timeZone, context.now);
  // Calculate extended range for data fetching to include tomorrow's data when available
  const extendedRange = dayRangesWithTomorrow[dayRangesWithTomorrow.length - 1];
  if (!extendedRange) {
    res.status(400).json({ error: 'Unable to construct aggregation window' });
    return;
  }
  
  const [dailyTotals, dailySkuRows] = await Promise.all([
    fetchDailyTotalRows(context.companyId, context.rangeStart, extendedRange.end, context.timeZone),
    fetchDailySkuRows(
      context.companyId,
      context.rangeStart,
      extendedRange.end,
      context.timeZone,
    ),
  ]);

  const points = buildSkuBreakdownSeries(dayRangesWithTomorrow, dailyTotals, dailySkuRows);
  const weekAverages =
    context.aggregation === 'week'
      ? buildWeekAverages(dayRangesWithTomorrow, points, context.now)
      : [];
  const responseRange = formatAppExclusiveRange(
    { start: extendedRange.start, end: extendedRange.end },
    context.timeZone,
  );

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    aggregation: context.aggregation,
    periods: context.periods,
    lookbackDays: context.lookbackDays,
    rangeStart: responseRange.start,
    rangeEnd: responseRange.end,
    points,
    weekAverages,
  });
});

router.post('/pick-entries/breakdown', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const timezoneContext = await buildTimezoneContext(req, res);
  if (!timezoneContext) {
    return;
  }

  const breakdownRequest = parsePickEntryBreakdownRequest(req.body);
  const breakdownWindow = buildPickEntryBreakdownWindow(
    breakdownRequest.aggregation,
    timezoneContext.timeZone,
    timezoneContext.now,
    breakdownRequest.showBars,
  );

  if (breakdownWindow.buckets.length === 0) {
    res.status(400).json({ error: 'Unable to construct breakdown window' });
    return;
  }

  const rows = await fetchPickEntryBreakdownRows(
    timezoneContext.companyId,
    timezoneContext.timeZone,
    breakdownWindow.rangeStart,
    breakdownWindow.rangeEnd,
    breakdownRequest.filters,
  );

  const { points, dailyTotals } = buildPickEntryBreakdownPoints(
    breakdownWindow.buckets,
    rows,
    breakdownRequest.breakdownBy,
    timezoneContext.timeZone,
  );

  const averages = buildPickEntryBreakdownAverages(
    breakdownRequest.aggregation,
    breakdownWindow.buckets,
    dailyTotals,
    timezoneContext.timeZone,
  );

  const availableFilters = buildPickEntryBreakdownAvailableFilters(
    rows,
    breakdownRequest.availableFilterDimensions,
  );

  const responseRange = formatAppExclusiveRange(
    { start: breakdownWindow.rangeStart, end: breakdownWindow.rangeEnd },
    timezoneContext.timeZone,
  );

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: timezoneContext.timeZone,
    aggregation: breakdownRequest.aggregation,
    breakdownBy: breakdownRequest.breakdownBy,
    showBars: breakdownWindow.buckets.length,
    rangeStart: responseRange.start,
    rangeEnd: responseRange.end,
    chartItemFocus: {
      sku: breakdownRequest.chartItemFocus.skuId,
      machine: breakdownRequest.chartItemFocus.machineId,
      location: breakdownRequest.chartItemFocus.locationId,
    },
    filters: {
      sku: breakdownRequest.filters.skuIds,
      machine: breakdownRequest.filters.machineIds,
      location: breakdownRequest.filters.locationIds,
    },
    availableFilters,
    points,
    averages,
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

router.get('/machines/pick-totals', setLogConfig({ level: 'minimal' }), async (req, res) => {
  const context = await buildTimezoneContext(req, res);
  if (!context) {
    return;
  }

  const lookbackDays = parseMachinePickLookbackDays(req.query.lookbackDays);
  const { rangeStart, rangeEnd } = buildTopSkuRange(context.timeZone, context.now, lookbackDays);

  const machineRows = await fetchMachinePickTotals(
    context.companyId,
    rangeStart,
    rangeEnd,
  );

  const responseRange = formatAppExclusiveRange({ start: rangeStart, end: rangeEnd }, context.timeZone);

  res.json({
    generatedAt: new Date().toISOString(),
    timeZone: context.timeZone,
    lookbackDays,
    rangeStart: responseRange.start,
    rangeEnd: responseRange.end,
    machines: machineRows
      .filter((row) => row.machine_id)
      .map((row) => ({
        machineId: row.machine_id!,
        machineCode: row.machine_code ?? 'Machine',
        machineDescription: row.machine_description ?? row.machine_code ?? 'Machine',
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

router.get('/packs/period-comparison', setLogConfig({ level: 'minimal' }), async (req, res) => {
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

router.get('/dashboard', setLogConfig({ level: 'minimal' }), async (req, res) => {
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
    machineTouches,
  ] = await Promise.all([
    fetchDashboardSkuMomentumRows(context.companyId, weekWindow),
    fetchDashboardMachineMomentumRows(context.companyId, weekWindow),
    fetchDashboardLocationMomentumRows(context.companyId, weekWindow),
    fetchDashboardSkuComparisonSegments(
      context.companyId,
      weekWindow,
    ),
    fetchDashboardSkuComparisonTotals(context.companyId, weekWindow),
    buildDashboardMachineTouchSeries(
      context.companyId,
      context.timeZone,
      context.now,
      DASHBOARD_MACHINE_TOUCH_WEEKS,
    ),
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
    machineTouches,
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

type PickEntryAggregation = (typeof PICK_ENTRY_AGGREGATIONS)[number];

type AggregatedLookbackContext = {
  companyId: string;
  timeZone: string;
  now: Date;
  aggregation: PickEntryAggregation;
  periods: number;
  lookbackDays: number;
  dayRanges: TimezoneDayRange[];
  rangeStart: Date;
  rangeEnd: Date;
};

type PickEntryBreakdownDimension = 'sku' | 'machine' | 'location';

type PickEntryBreakdownRequest = {
  aggregation: PickEntryAggregation;
  breakdownBy: PickEntryBreakdownDimension;
  showBars: number;
  chartItemFocus: {
    skuId: string | null;
    machineId: string | null;
    locationId: string | null;
  };
  filters: {
    skuIds: string[];
    machineIds: string[];
    locationIds: string[];
  };
  availableFilterDimensions: PickEntryBreakdownDimension[];
};

type PickEntryBreakdownBucket = {
  key: string;
  start: Date;
  end: Date;
  xValue: string;
  dayLabels: string[];
};

type PickEntryBreakdownItem = {
  id: string;
  friendlyName: string;
  totalItems: number;
};

type PickEntryBreakdownPoint = {
  xValue: string;
  start: string;
  end: string;
  totalItems: number;
  items: PickEntryBreakdownItem[];
};

type PickEntryBreakdownAverage = {
  start: string;
  end: string;
  dates: string[];
  average: number;
};

type PickEntryBreakdownAvailableFilters = {
  sku: Array<{ id: string; displayName: string }>;
  machine: Array<{ id: string; displayName: string }>;
  location: Array<{ id: string; displayName: string }>;
};

type PickEntryBreakdownWindow = {
  buckets: PickEntryBreakdownBucket[];
  rangeStart: Date;
  rangeEnd: Date;
};

type PeriodType = (typeof PERIOD_TYPES)[number];

type PeriodWindow = {
  start: Date;
  end: Date;
};

type PickEntryWeekAverage = {
  weekStart: string;
  weekEnd: string;
  dates: string[];
  average: number;
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

  const now = new Date();
  const timeZone = await resolveCompanyTimezone(req.auth.companyId);

  return {
    companyId: req.auth.companyId,
    timeZone,
    now,
  };
}

async function buildAggregatedLookbackContext(
  req: Request,
  res: Response,
): Promise<AggregatedLookbackContext | null> {
  const timezoneContext = await buildTimezoneContext(req, res);
  if (!timezoneContext) {
    return null;
  }

  const aggregation = parsePickEntryAggregation(req.query.aggregation);
  const periods = parseAggregationPeriods(req.query.periods);
  const lookbackDays = getAggregationLookbackDays(aggregation, periods);
  const dayRanges = buildDayRanges(timezoneContext.timeZone, lookbackDays, timezoneContext.now);

  if (dayRanges.length === 0) {
    res.status(400).json({ error: 'Unable to construct aggregation window' });
    return null;
  }

  return {
    ...timezoneContext,
    aggregation,
    periods,
    lookbackDays,
    dayRanges,
    rangeStart: dayRanges[0]!.start,
    rangeEnd: dayRanges[dayRanges.length - 1]!.end,
  };
}

function parsePickEntryAggregation(value: unknown): PickEntryAggregation {
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if ((PICK_ENTRY_AGGREGATIONS as readonly string[]).includes(normalized)) {
      return normalized as PickEntryAggregation;
    }
  }
  return 'week';
}

function getAggregationBaseDays(aggregation: PickEntryAggregation): number {
  switch (aggregation) {
    case 'week':
      return 7;
    case 'month':
      return 30;
    case 'quarter':
      return 90;
    default:
      return LOOKBACK_DEFAULT;
  }
}

function parseAggregationPeriods(value: unknown): number {
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return clamp(parsed, PICK_ENTRY_PERIOD_MIN, PICK_ENTRY_PERIOD_MAX);
    }
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return clamp(Math.trunc(value), PICK_ENTRY_PERIOD_MIN, PICK_ENTRY_PERIOD_MAX);
  }
  return PICK_ENTRY_DEFAULT_PERIODS;
}

function getAggregationLookbackDays(aggregation: PickEntryAggregation, periods: number): number {
  const baseDays = getAggregationBaseDays(aggregation);
  const raw = baseDays * Math.max(periods, 1);
  return clamp(raw, baseDays, PICK_ENTRY_LOOKBACK_MAX);
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

function parseMachinePickLookbackDays(value: unknown): number {
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return clamp(parsed, LOOKBACK_MIN, LOOKBACK_MAX);
    }
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return clamp(Math.trunc(value), LOOKBACK_MIN, LOOKBACK_MAX);
  }
  return MACHINE_PICK_LOOKBACK_DEFAULT;
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

async function fetchDailyTotalRows(
  companyId: string,
  rangeStart: Date,
  rangeEnd: Date,
  timeZone: string,
) {
  return prisma.$queryRaw<DailyTotalRow[]>(
    Prisma.sql`
      SELECT
        DATE_FORMAT(CONVERT_TZ(scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS day_label,
        SUM(count) AS total_items
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${rangeStart}
        AND scheduledFor < ${rangeEnd}
      GROUP BY day_label
      ORDER BY day_label ASC
    `,
  );
}

async function fetchDailySkuRows(
  companyId: string,
  rangeStart: Date,
  rangeEnd: Date,
  timeZone: string,
) {
  return prisma.$queryRaw<DailySkuRow[]>(
    Prisma.sql`
      SELECT
        DATE_FORMAT(CONVERT_TZ(scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS day_label,
        COALESCE(sku_id, 'unknown-sku') AS sku_id,
        COALESCE(sku_code, 'Unknown SKU') AS sku_code,
        COALESCE(sku_name, sku_code, 'Unknown SKU') AS sku_name,
        SUM(count) AS total_items
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${rangeStart}
        AND scheduledFor < ${rangeEnd}
      GROUP BY day_label, sku_id, sku_code, sku_name
      ORDER BY day_label ASC, total_items DESC
    `,
  );
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
            DATE_FORMAT(CONVERT_TZ(scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS converted_date,
            count AS total_items,
            CASE WHEN is_picked THEN count ELSE 0 END AS items_packed
          FROM v_pick_entry_details
          WHERE companyId = ${companyId}
            AND CONVERT_TZ(scheduledFor, 'UTC', ${timeZone}) >= DATE_SUB(CONVERT_TZ(CURRENT_TIMESTAMP(), 'UTC', ${timeZone}), INTERVAL ${Prisma.raw(String(trailingDays))} DAY)
            AND CONVERT_TZ(scheduledFor, 'UTC', ${timeZone}) < DATE_ADD(CONVERT_TZ(CURRENT_TIMESTAMP(), 'UTC', ${timeZone}), INTERVAL 2 DAY)
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
          location_id,
          location_name,
          machine_id,
          machine_code,
          machine_description,
          SUM(count) AS total_items
        FROM v_pick_entry_details
        WHERE companyId = ${companyId}
          AND scheduledFor >= ${rangeStart}
          AND scheduledFor < ${rangeEnd}
        GROUP BY location_id, location_name, machine_id, machine_code
        HAVING SUM(count) > 0
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
  const locationFilter = locationId ? Prisma.sql`AND location_id = ${locationId}` : Prisma.sql``;
  const machineFilter = machineId ? Prisma.sql`AND machine_id = ${machineId}` : Prisma.sql``;

  return prisma.$queryRaw<TopSkuRow[]>(
    Prisma.sql`
      SELECT
        sku_id,
        sku_code,
        sku_name,
        sku_type,
        SUM(count) AS total_picked
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${rangeStart}
        AND scheduledFor < ${rangeEnd}
        ${locationFilter}
        ${machineFilter}
      GROUP BY sku_id, sku_code, sku_name, sku_type
      HAVING SUM(count) > 0
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
          location_id,
          SUM(count) AS total_items
        FROM v_pick_entry_details
        WHERE companyId = ${companyId}
          AND scheduledFor IS NOT NULL
          AND scheduledFor >= ${rangeStart}
          AND scheduledFor < ${rangeEnd}
          AND location_id IS NOT NULL
        GROUP BY location_id
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
          machine_id,
          SUM(count) AS total_items
        FROM v_pick_entry_details
        WHERE companyId = ${companyId}
          AND scheduledFor IS NOT NULL
          AND scheduledFor >= ${rangeStart}
          AND scheduledFor < ${rangeEnd}
        GROUP BY machine_id
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

async function fetchMachinePickTotals(companyId: string, rangeStart: Date, rangeEnd: Date) {
  return prisma.$queryRaw<MachinePickTotalRow[]>(
    Prisma.sql`
      SELECT
        machine_id,
        machine_code,
        machine_description,
        SUM(count) AS total_items
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND machine_id IS NOT NULL
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${rangeStart}
        AND scheduledFor < ${rangeEnd}
      GROUP BY machine_id, machine_code, machine_description
      HAVING SUM(count) > 0
      ORDER BY total_items DESC, machine_code ASC
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
        location_id,
        location_name,
        location_address AS address,
        SUM(count) AS total_packed
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND is_picked
        AND pickedAt IS NOT NULL
        AND pickedAt >= ${rangeStart}
        AND pickedAt < ${rangeEnd}
      GROUP BY location_id, location_name, location_address
      HAVING SUM(count) > 0
      ORDER BY total_packed DESC, location_name ASC
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
        machine_id,
        machine_code,
        machine_description,
        location_id,
        location_name,
        SUM(count) AS total_packed
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND is_picked
        AND pickedAt IS NOT NULL
        AND pickedAt >= ${rangeStart}
        AND pickedAt < ${rangeEnd}
      GROUP BY machine_id, machine_code, machine_description, location_id, location_name
      HAVING SUM(count) > 0
      ORDER BY total_packed DESC, machine_code ASC
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
        sku_id,
        sku_code,
        sku_name,
        sku_type,
        sku_category AS category,
        SUM(count) AS total_packed
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND is_picked
        AND pickedAt IS NOT NULL
        AND pickedAt >= ${rangeStart}
        AND pickedAt < ${rangeEnd}
      GROUP BY sku_id, sku_code, sku_name, sku_type, sku_category
      HAVING SUM(count) > 0
      ORDER BY total_packed DESC, sku_code ASC
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

type PickEntryPoint = {
  date: string;
  start: string;
  end: string;
  totalItems: number;
  skus: Array<{
    skuId: string;
    skuCode: string;
    skuName: string;
    totalItems: number;
  }>;
};

function buildSkuBreakdownSeries(
  dayRanges: TimezoneDayRange[],
  totalRows: DailyTotalRow[],
  skuRows: DailySkuRow[],
): PickEntryPoint[] {
  const targetTimeZone = dayRanges[0]?.timeZone ?? 'UTC';
  const totalsByLabel = new Map<string, number>();
  const skusByLabel = new Map<
    string,
    Array<{
      skuId: string;
      skuCode: string;
      skuName: string;
      totalItems: number;
    }>
  >();

  for (const row of totalRows) {
    const normalizedLabel = normalizeDayLabel(row.day_label, targetTimeZone);
    if (!normalizedLabel) {
      continue;
    }
    totalsByLabel.set(normalizedLabel, Math.max(toNumber(row.total_items), 0));
  }

  for (const row of skuRows) {
    const normalizedLabel = normalizeDayLabel(row.day_label, targetTimeZone);
    if (!normalizedLabel) {
      continue;
    }
    const skuId = (row.sku_id ?? 'unknown-sku').trim() || 'unknown-sku';
    const skuCode = row.sku_code ?? 'SKU';
    const skuName = (row.sku_name ?? skuCode ?? 'SKU').trim() || skuCode || 'SKU';
    const totalItems = Math.max(toNumber(row.total_items), 0);
    if (totalItems <= 0) {
      continue;
    }
    const segment = { skuId, skuCode, skuName, totalItems };
    const existing = skusByLabel.get(normalizedLabel) ?? [];
    existing.push(segment);
    skusByLabel.set(normalizedLabel, existing);
  }

  return dayRanges.map((range) => {
    const totalItems = totalsByLabel.get(range.label) ?? 0;
    const daySkus = (skusByLabel.get(range.label) ?? []).sort(
      (a, b) => b.totalItems - a.totalItems,
    );
    const segmentTotal = daySkus.reduce((sum, entry) => sum + entry.totalItems, 0);
    const otherItems = Math.max(totalItems - segmentTotal, 0);
    const normalizedSkus =
      otherItems > 0
        ? [
            ...daySkus,
            { skuId: 'other', skuCode: 'Other', skuName: 'Other', totalItems: otherItems },
          ]
        : daySkus;

    return {
      date: range.label,
      start: range.label,
      end: range.label,
      totalItems,
      skus: normalizedSkus,
    };
  });
}

function buildWeekAverages(
  dayRanges: TimezoneDayRange[],
  points: PickEntryPoint[],
  reference: Date,
): PickEntryWeekAverage[] {
  if (dayRanges.length === 0) {
    return [];
  }

  const totalsByLabel = new Map<string, number>();
  for (const point of points) {
    totalsByLabel.set(point.date, Math.max(point.totalItems, 0));
  }

  const weekBuckets = new Map<
    string,
    {
      start: Date;
      end: Date;
      timeZone: string;
      dates: string[];
      totals: number[];
    }
  >();

  for (const range of dayRanges) {
    const weekStart = getIsoWeekStart(range.timeZone, range.start);
    const weekEnd = new Date(weekStart.getTime() + WEEK_IN_MS);
    const weekKey = formatDateInTimezone(weekStart, range.timeZone);
    const totalItems = totalsByLabel.get(range.label) ?? 0;

    if (!weekBuckets.has(weekKey)) {
      weekBuckets.set(weekKey, {
        start: weekStart,
        end: weekEnd,
        timeZone: range.timeZone,
        dates: [],
        totals: [],
      });
    }

    const bucket = weekBuckets.get(weekKey)!;
    bucket.dates.push(range.label);
    if (totalItems > 0) {
      bucket.totals.push(totalItems);
    }
  }

  return Array.from(weekBuckets.values())
    .sort((a, b) => a.start.getTime() - b.start.getTime())
    .map((bucket) => {
      const dayCount = bucket.totals.length || 1;
      const total = bucket.totals.reduce((sum, value) => sum + value, 0);
      const average = dayCount > 0 ? total / dayCount : 0;
      return {
        weekStart: formatDateInTimezone(bucket.start, bucket.timeZone),
        weekEnd: formatDateInTimezone(new Date(bucket.end.getTime() - DAY_IN_MS), bucket.timeZone),
        dates: [...bucket.dates].sort(),
        average: Number(average.toFixed(2)),
      };
    });
}

function parsePickEntryBreakdownRequest(body: unknown): PickEntryBreakdownRequest {
  const payload = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
  const aggregation = parsePickEntryAggregation(payload.aggregateBy ?? payload.aggregation);
  const chartItemFocus = parseChartItemFocus(payload.chartItemFocus);
  const focusType = determineBreakdownFocus(chartItemFocus);
  const filters = mergeFocusWithFilters(parseBreakdownFilters(payload.filter), chartItemFocus);
  const { breakdownBy, availableFilterDimensions } = deriveBreakdownRulesFromFocus(focusType);
  const showBars = parseBreakdownShowBars(payload.showBars, aggregation);

  return {
    aggregation,
    breakdownBy,
    showBars,
    chartItemFocus,
    filters,
    availableFilterDimensions,
  };
}

function parseChartItemFocus(raw: unknown) {
  const payload = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const skuId = normalizeIdValue(payload.sku ?? payload.skuId);
  const machineId = normalizeIdValue(payload.machine ?? payload.machineId);
  const locationId = normalizeIdValue(payload.location ?? payload.locationId);
  return { skuId, machineId, locationId };
}

type PickEntryBreakdownFocus = 'sku' | 'machine' | 'location' | 'none';

function determineBreakdownFocus(focus: { skuId: string | null; machineId: string | null; locationId: string | null }): PickEntryBreakdownFocus {
  if (focus.skuId) {
    return 'sku';
  }
  if (focus.machineId) {
    return 'machine';
  }
  if (focus.locationId) {
    return 'location';
  }
  return 'none';
}

function deriveBreakdownRulesFromFocus(
  focus: PickEntryBreakdownFocus,
): {
  breakdownBy: PickEntryBreakdownDimension;
  availableFilterDimensions: PickEntryBreakdownDimension[];
} {
  if (focus === 'sku') {
    return { breakdownBy: 'machine', availableFilterDimensions: ['machine', 'location'] };
  }
  if (focus === 'machine') {
    return { breakdownBy: 'sku', availableFilterDimensions: ['sku'] };
  }
  if (focus === 'location') {
    return { breakdownBy: 'machine', availableFilterDimensions: ['machine', 'sku'] };
  }
  return {
    breakdownBy: 'sku',
    availableFilterDimensions: ['sku', 'machine', 'location'],
  };
}

function parseBreakdownFilters(raw: unknown) {
  const payload = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  return {
    skuIds: normalizeIdArray(payload.sku ?? payload.skuIds),
    machineIds: normalizeIdArray(payload.machine ?? payload.machineIds),
    locationIds: normalizeIdArray(payload.location ?? payload.locationIds),
  };
}

function mergeFocusWithFilters(
  filters: { skuIds: string[]; machineIds: string[]; locationIds: string[] },
  focus: { skuId: string | null; machineId: string | null; locationId: string | null },
) {
  const skuIds = [...filters.skuIds, ...(focus.skuId ? [focus.skuId] : [])];
  const machineIds = [...filters.machineIds, ...(focus.machineId ? [focus.machineId] : [])];
  const locationIds = [...filters.locationIds, ...(focus.locationId ? [focus.locationId] : [])];

  return {
    skuIds: uniqueIds(skuIds),
    machineIds: uniqueIds(machineIds),
    locationIds: uniqueIds(locationIds),
  };
}

function parseBreakdownShowBars(raw: unknown, aggregation: PickEntryAggregation): number {
  const defaultValue = PICK_ENTRY_BREAKDOWN_SHOW_BARS[aggregation] ?? PICK_ENTRY_BREAKDOWN_SHOW_BARS.week;

  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return clamp(Math.trunc(raw), 1, PICK_ENTRY_BREAKDOWN_MAX_BARS);
  }

  if (raw && typeof raw === 'object') {
    const candidate = (raw as Record<string, unknown>)[aggregation];
    if (typeof candidate === 'number' && Number.isFinite(candidate)) {
      return clamp(Math.trunc(candidate), 1, PICK_ENTRY_BREAKDOWN_MAX_BARS);
    }
  }

  return defaultValue;
}

function buildPickEntryBreakdownWindow(
  aggregation: PickEntryAggregation,
  timeZone: string,
  reference: Date,
  showBars: number,
): PickEntryBreakdownWindow {
  switch (aggregation) {
    case 'week':
      return buildDailyBreakdownWindow(timeZone, reference, showBars);
    case 'month':
      return buildWeeklyBreakdownWindow(timeZone, reference, showBars);
    case 'quarter':
    default:
      return buildMonthlyBreakdownWindow(timeZone, reference, showBars);
  }
}

function buildDailyBreakdownWindow(
  timeZone: string,
  reference: Date,
  showBars: number,
): PickEntryBreakdownWindow {
  const futureBuckets = 1;
  const targetBars = Math.max(showBars, futureBuckets + 1);
  const pastBuckets = Math.max(targetBars - 1 - futureBuckets, 0);
  const buckets: PickEntryBreakdownBucket[] = [];

  for (let offset = pastBuckets; offset >= -futureBuckets; offset -= 1) {
    const dayRange = getTimezoneDayRange({ timeZone, dayOffset: -offset, reference });
    buckets.push({
      key: `${dayRange.label}-day`,
      start: dayRange.start,
      end: dayRange.end,
      xValue: dayRange.label,
      dayLabels: [dayRange.label],
    });
  }

  const rangeStart = buckets[0]?.start ?? getTimezoneDayRange({ timeZone, reference }).start;
  const rangeEnd = buckets[buckets.length - 1]?.end ?? getTimezoneDayRange({ timeZone, reference }).end;

  return { buckets, rangeStart, rangeEnd };
}

function buildWeeklyBreakdownWindow(
  timeZone: string,
  reference: Date,
  showBars: number,
): PickEntryBreakdownWindow {
  const futureBuckets = 1;
  const targetBars = Math.max(showBars, futureBuckets + 1);
  const pastBuckets = Math.max(targetBars - 1 - futureBuckets, 0);
  const currentWeekStart = getIsoWeekStart(timeZone, reference);
  const buckets: PickEntryBreakdownBucket[] = [];

  for (let offset = pastBuckets; offset >= -futureBuckets; offset -= 1) {
    const start = new Date(currentWeekStart.getTime() - offset * WEEK_IN_MS);
    const end = new Date(start.getTime() + WEEK_IN_MS);
    buckets.push({
      key: `${formatDateInTimezone(start, timeZone)}-week`,
      start,
      end,
      xValue: `W${getIsoWeekNumber(timeZone, start)}`,
      dayLabels: buildDayLabelsForRange(start, end, timeZone),
    });
  }

  const rangeStart = buckets[0]?.start ?? currentWeekStart;
  const rangeEnd = buckets[buckets.length - 1]?.end ?? new Date(currentWeekStart.getTime() + WEEK_IN_MS);

  return { buckets, rangeStart, rangeEnd };
}

function buildMonthlyBreakdownWindow(
  timeZone: string,
  reference: Date,
  showBars: number,
): PickEntryBreakdownWindow {
  const futureBuckets = 0;
  const targetBars = Math.max(showBars, 1);
  const pastBuckets = Math.max(targetBars - 1 - futureBuckets, 0);
  const buckets: PickEntryBreakdownBucket[] = [];

  for (let offset = pastBuckets; offset >= -futureBuckets; offset -= 1) {
    const window = getMonthWindow(timeZone, reference, offset);
    buckets.push({
      key: `${formatDateInTimezone(window.start, timeZone)}-month`,
      start: window.start,
      end: window.end,
      xValue: formatMonthLabel(window.start, timeZone),
      dayLabels: buildDayLabelsForRange(window.start, window.end, timeZone),
    });
  }

  const currentMonthWindow = getMonthWindow(timeZone, reference, 0);
  const rangeStart = buckets[0]?.start ?? currentMonthWindow.start;
  const rangeEnd = buckets[buckets.length - 1]?.end ?? currentMonthWindow.end;

  return { buckets, rangeStart, rangeEnd };
}

async function fetchPickEntryBreakdownRows(
  companyId: string,
  timeZone: string,
  rangeStart: Date,
  rangeEnd: Date,
  filters: { skuIds: string[]; machineIds: string[]; locationIds: string[] },
): Promise<PickEntryBreakdownRow[]> {
  const skuFilterClause =
    filters.skuIds.length > 0
      ? Prisma.sql`AND sku_id IN (${Prisma.join(filters.skuIds)})`
      : Prisma.sql``;
  const machineFilterClause =
    filters.machineIds.length > 0
      ? Prisma.sql`AND machine_id IN (${Prisma.join(filters.machineIds)})`
      : Prisma.sql``;
  const locationFilterClause =
    filters.locationIds.length > 0
      ? Prisma.sql`AND location_id IN (${Prisma.join(filters.locationIds)})`
      : Prisma.sql``;

  return prisma.$queryRaw<PickEntryBreakdownRow[]>(
    Prisma.sql`
      SELECT
        DATE_FORMAT(CONVERT_TZ(scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS day_label,
        sku_id,
        sku_code,
        sku_name,
        machine_id,
        machine_code,
        machine_description,
        location_id,
        location_name,
        SUM(count) AS total_items
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${rangeStart}
        AND scheduledFor < ${rangeEnd}
        ${skuFilterClause}
        ${machineFilterClause}
        ${locationFilterClause}
      GROUP BY
        day_label,
        sku_id,
        sku_code,
        sku_name,
        machine_id,
        machine_code,
        machine_description,
        location_id,
        location_name
      ORDER BY day_label ASC
    `,
  );
}

function buildPickEntryBreakdownPoints(
  buckets: PickEntryBreakdownBucket[],
  rows: PickEntryBreakdownRow[],
  breakdownBy: PickEntryBreakdownDimension,
  timeZone: string,
): { points: PickEntryBreakdownPoint[]; dailyTotals: Map<string, number> } {
  const bucketByDay = new Map<string, string>();
  const bucketData = new Map<
    string,
    {
      bucket: PickEntryBreakdownBucket;
      totalItems: number;
      segments: Map<string, PickEntryBreakdownItem>;
    }
  >();
  const dailyTotals = new Map<string, number>();

  for (const bucket of buckets) {
    bucketData.set(bucket.key, { bucket, totalItems: 0, segments: new Map() });
    for (const dayLabel of bucket.dayLabels) {
      bucketByDay.set(dayLabel, bucket.key);
      if (!dailyTotals.has(dayLabel)) {
        dailyTotals.set(dayLabel, 0);
      }
    }
  }

  for (const row of rows) {
    const dayLabel = normalizeDayLabel(row.day_label, timeZone);
    if (!dayLabel) {
      continue;
    }
    const bucketKey = bucketByDay.get(dayLabel);
    if (!bucketKey) {
      continue;
    }

    const totalItems = Math.max(toNumber(row.total_items), 0);
    if (totalItems > 0) {
      dailyTotals.set(dayLabel, (dailyTotals.get(dayLabel) ?? 0) + totalItems);
    }

    const bucketEntry = bucketData.get(bucketKey);
    if (!bucketEntry || totalItems <= 0) {
      continue;
    }

    bucketEntry.totalItems += totalItems;
    const segment = mapBreakdownSegment(breakdownBy, row);
    const existing = bucketEntry.segments.get(segment.id);
    if (existing) {
      existing.totalItems += totalItems;
    } else {
      bucketEntry.segments.set(segment.id, { ...segment, totalItems });
    }
  }

  const points = buckets.map((bucket) => {
    const bucketEntry = bucketData.get(bucket.key);
    const items =
      bucketEntry && bucketEntry.segments.size > 0
        ? Array.from(bucketEntry.segments.values()).sort((a, b) => b.totalItems - a.totalItems)
        : [];

    return {
      xValue: bucket.xValue,
      start: formatDateInTimezone(bucket.start, timeZone),
      end: formatDateInTimezone(new Date(bucket.end.getTime() - DAY_IN_MS), timeZone),
      totalItems: bucketEntry?.totalItems ?? 0,
      items,
    };
  });

  return { points, dailyTotals };
}

function buildPickEntryBreakdownAverages(
  aggregation: PickEntryAggregation,
  buckets: PickEntryBreakdownBucket[],
  dailyTotals: Map<string, number>,
  timeZone: string,
): PickEntryBreakdownAverage[] {
  if (aggregation === 'week') {
    // Group by ISO week to keep the original week overlay behavior
    const weekGroups = new Map<
      string,
      { start: Date; end: Date; labels: string[]; totals: number[] }
    >();

    for (const bucket of buckets) {
      for (const label of bucket.dayLabels) {
        const date = parseDateLabelInTimezone(label, timeZone);
        const weekStart = getIsoWeekStart(timeZone, date);
        const weekEnd = new Date(weekStart.getTime() + WEEK_IN_MS);
        const key = formatDateInTimezone(weekStart, timeZone);
        const total = Math.max(dailyTotals.get(label) ?? 0, 0);
        if (!weekGroups.has(key)) {
          weekGroups.set(key, { start: weekStart, end: weekEnd, labels: [], totals: [] });
        }
        const group = weekGroups.get(key)!;
        group.labels.push(label);
        if (total > 0) {
          group.totals.push(total);
        }
      }
    }

    return Array.from(weekGroups.values())
      .sort((a, b) => a.start.getTime() - b.start.getTime())
      .map((group) => {
        const averageRaw =
          group.totals.length > 0
            ? group.totals.reduce((sum, value) => sum + value, 0) / group.totals.length
            : 0;
        return {
          start: formatDateInTimezone(group.start, timeZone),
          end: formatDateInTimezone(new Date(group.end.getTime() - DAY_IN_MS), timeZone),
          dates: [...group.labels].sort(),
          average: Number(averageRaw.toFixed(2)),
        };
      });
  }

  if (aggregation === 'quarter') {
    const groupedByQuarter = new Map<
      number,
      {
        buckets: PickEntryBreakdownBucket[];
      }
    >();

    for (const bucket of buckets) {
      const { year, month } = getLocalDatePartsInTimezone(bucket.start, timeZone);
      const quarterIndex = Math.floor((month - 1) / 3);
      const quarterKey = year * QUARTERS_IN_YEAR + quarterIndex;
      if (!groupedByQuarter.has(quarterKey)) {
        groupedByQuarter.set(quarterKey, { buckets: [] });
      }
      groupedByQuarter.get(quarterKey)!.buckets.push(bucket);
    }

    return Array.from(groupedByQuarter.entries())
      .sort((a, b) => a[0] - b[0])
      .map(([, group]) => {
        const orderedBuckets = group.buckets.sort((a, b) => a.start.getTime() - b.start.getTime());
        const bucketTotals = orderedBuckets.map((bucket) => sumBucketTotals(bucket, dailyTotals));
        const nonZeroTotals = bucketTotals.filter((total) => total > 0);
        const averageRaw =
          nonZeroTotals.length > 0
            ? nonZeroTotals.reduce((sum, value) => sum + value, 0) / nonZeroTotals.length
            : 0;
        const allLabels = orderedBuckets.flatMap((bucket) => bucket.dayLabels);

        return {
          start: formatDateInTimezone(orderedBuckets[0]!.start, timeZone),
          end: formatDateInTimezone(
            new Date(orderedBuckets[orderedBuckets.length - 1]!.end.getTime() - DAY_IN_MS),
            timeZone,
          ),
          dates: [...new Set(allLabels)].sort(),
          average: Number(averageRaw.toFixed(2)),
        };
      });
  }

  // Month aggregation: align averages per bucket and ignore zero-value days
  const monthGroups = new Map<
    string,
    {
      start: Date;
      end: Date;
      labels: Set<string>;
      totals: number[];
      nonZeroTotals: number[];
    }
  >();

  for (const bucket of buckets) {
    // Anchor the week to its final day so weeks containing the 1st of a month count toward that month.
    const anchorDate = new Date(bucket.end.getTime() - DAY_IN_MS);
    const { year, month } = getLocalDatePartsInTimezone(anchorDate, timeZone);
    const monthKey = `${year}-${String(month).padStart(2, '0')}`;
    const bucketTotal = Math.max(sumBucketTotals(bucket, dailyTotals), 0);

    if (!monthGroups.has(monthKey)) {
      monthGroups.set(monthKey, {
        start: bucket.start,
        end: bucket.end,
        labels: new Set(bucket.dayLabels),
        totals: [bucketTotal],
        nonZeroTotals: bucketTotal > 0 ? [bucketTotal] : [],
      });
    } else {
      const group = monthGroups.get(monthKey)!;
      group.start = new Date(Math.min(group.start.getTime(), bucket.start.getTime()));
      group.end = new Date(Math.max(group.end.getTime(), bucket.end.getTime()));
      bucket.dayLabels.forEach((label) => group.labels.add(label));
      group.totals.push(bucketTotal);
      if (bucketTotal > 0) {
        group.nonZeroTotals.push(bucketTotal);
      }
    }
  }

  return Array.from(monthGroups.entries())
    .sort(([aKey], [bKey]) => (aKey < bKey ? -1 : 1))
    .map(([, group]) => {
      const averageRaw =
        group.nonZeroTotals.length > 0
          ? group.nonZeroTotals.reduce((sum, value) => sum + value, 0) / group.nonZeroTotals.length
          : 0;

      return {
        start: formatDateInTimezone(group.start, timeZone),
        end: formatDateInTimezone(new Date(group.end.getTime() - DAY_IN_MS), timeZone),
        dates: Array.from(group.labels).sort(),
        average: Number(averageRaw.toFixed(2)),
      };
    });
}

function sumBucketTotals(bucket: PickEntryBreakdownBucket, dailyTotals: Map<string, number>): number {
  return bucket.dayLabels.reduce((sum, label) => sum + Math.max(dailyTotals.get(label) ?? 0, 0), 0);
}

function buildPickEntryBreakdownAvailableFilters(
  rows: PickEntryBreakdownRow[],
  allowedDimensions: PickEntryBreakdownDimension[],
): PickEntryBreakdownAvailableFilters {
  const skuOptions = new Map<string, string>();
  const machineOptions = new Map<string, string>();
  const locationOptions = new Map<string, string>();

  for (const row of rows) {
    const totalItems = Math.max(toNumber(row.total_items), 0);
    if (totalItems <= 0) {
      continue;
    }
    if (allowedDimensions.includes('sku')) {
      const skuId = normalizeIdValue(row.sku_id);
      if (skuId) {
        const name = (row.sku_name ?? row.sku_code ?? 'SKU').trim() || (row.sku_code ?? 'SKU');
        skuOptions.set(skuId, name);
      }
    }
    if (allowedDimensions.includes('machine')) {
      const machineId = normalizeIdValue(row.machine_id);
      if (machineId) {
        const name =
          (row.machine_description ?? row.machine_code ?? 'Machine').trim() ||
          (row.machine_code ?? 'Machine');
        machineOptions.set(machineId, name);
      }
    }
    if (allowedDimensions.includes('location')) {
      const locationId = normalizeIdValue(row.location_id);
      if (locationId) {
        const name = (row.location_name ?? 'Location').trim() || 'Location';
        locationOptions.set(locationId, name);
      }
    }
  }

  const mapOptions = (optionMap: Map<string, string>) =>
    Array.from(optionMap.entries())
      .map(([id, displayName]) => ({ id, displayName }))
      .sort((a, b) => a.displayName.localeCompare(b.displayName, 'en'));

  return {
    sku: allowedDimensions.includes('sku') ? mapOptions(skuOptions) : [],
    machine: allowedDimensions.includes('machine') ? mapOptions(machineOptions) : [],
    location: allowedDimensions.includes('location') ? mapOptions(locationOptions) : [],
  };
}

function mapBreakdownSegment(
  breakdownBy: PickEntryBreakdownDimension,
  row: PickEntryBreakdownRow,
): PickEntryBreakdownItem {
  if (breakdownBy === 'machine') {
    const id = normalizeIdValue(row.machine_id) ?? 'unknown-machine';
    const friendlyName =
      (row.machine_description ?? row.machine_code ?? 'Machine').trim() ||
      (row.machine_code ?? 'Machine');
    return { id, friendlyName, totalItems: 0 };
  }

  if (breakdownBy === 'location') {
    const id = normalizeIdValue(row.location_id) ?? 'unknown-location';
    const friendlyName = (row.location_name ?? 'Location').trim() || 'Location';
    return { id, friendlyName, totalItems: 0 };
  }

  const id = normalizeIdValue(row.sku_id) ?? 'unknown-sku';
  const friendlyName = (row.sku_name ?? row.sku_code ?? 'SKU').trim() || (row.sku_code ?? 'SKU');
  return { id, friendlyName, totalItems: 0 };
}

function resolveAverageGroupingWindow(
  aggregation: PickEntryAggregation,
  reference: Date,
  timeZone: string,
) {
  if (aggregation === 'week') {
    const start = getIsoWeekStart(timeZone, reference);
    const end = new Date(start.getTime() + WEEK_IN_MS);
    return { key: `${formatDateInTimezone(start, timeZone)}-week`, start, end };
  }
  if (aggregation === 'month') {
    const window = getMonthWindow(timeZone, reference, 0);
    return { key: `${formatDateInTimezone(window.start, timeZone)}-month`, start: window.start, end: window.end };
  }
  const window = getQuarterWindow(timeZone, reference, 0);
  return { key: `${formatDateInTimezone(window.start, timeZone)}-quarter`, start: window.start, end: window.end };
}

function formatMonthLabel(reference: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-US', { month: 'long', timeZone }).format(reference);
}

function buildDayLabelsForRange(start: Date, end: Date, timeZone: string): string[] {
  const labels: string[] = [];
  let cursor = start;
  while (cursor < end) {
    const range = getTimezoneDayRange({ timeZone, reference: cursor });
    if (!labels.includes(range.label)) {
      labels.push(range.label);
    }
    cursor = range.end;
  }
  return labels;
}

function getIsoWeekNumber(timeZone: string, reference: Date): number {
  const { year, month, day } = getLocalDatePartsInTimezone(reference, timeZone);
  const date = new Date(Date.UTC(year, month - 1, day));
  const dayNumber = (date.getUTCDay() + 6) % 7;
  date.setUTCDate(date.getUTCDate() - dayNumber + 3);
  const firstThursday = date.getTime();
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  return Math.round((firstThursday - yearStart.getTime()) / (7 * DAY_IN_MS)) + 1;
}

function parseDateLabelInTimezone(label: string, timeZone: string): Date {
  const date = new Date(`${label}T00:00:00Z`);
  return convertDateToTimezoneMidnight(date, timeZone);
}

function normalizeIdArray(raw: unknown): string[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  return uniqueIds(
    raw
      .map((value) => normalizeIdValue(value))
      .filter((value): value is string => typeof value === 'string' && value.length > 0),
  );
}

function normalizeIdValue(raw: unknown): string | null {
  if (typeof raw !== 'string') {
    return null;
  }
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function uniqueIds(values: string[]): string[] {
  return Array.from(new Set(values.filter((value) => value && value.length > 0)));
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
      SELECT COALESCE(SUM(count), 0) AS total_items
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${rangeStart}
        AND scheduledFor < ${rangeEnd}
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

async function countMachinesTouched(
  companyId: string,
  rangeStart: Date,
  rangeEnd: Date,
): Promise<number> {
  const [row] = await prisma.$queryRaw<{ total_machines: bigint | number | string | null }[]>(
    Prisma.sql`
      SELECT COUNT(DISTINCT machine_id) AS total_machines
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND machine_id IS NOT NULL
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${rangeStart}
        AND scheduledFor < ${rangeEnd}
    `,
  );

  return Math.max(toNumber(row?.total_machines ?? 0), 0);
}

async function buildDashboardMachineTouchSeries(
  companyId: string,
  timeZone: string,
  reference: Date,
  weekCount: number,
): Promise<DashboardMachineTouchPoint[]> {
  const totalWeeks = Math.max(weekCount, 1);
  const currentWeekStart = getIsoWeekStart(timeZone, reference);
  const weekWindows = Array.from({ length: totalWeeks }, (_, index) => {
    const offset = totalWeeks - 1 - index;
    const start = new Date(currentWeekStart.getTime() - offset * WEEK_IN_MS);
    return {
      start,
      end: new Date(start.getTime() + WEEK_IN_MS),
    };
  });

  const totals = await Promise.all(
    weekWindows.map((window) => countMachinesTouched(companyId, window.start, window.end)),
  );

  return weekWindows.map((window, index) => {
    const range = formatAppExclusiveRange({ start: window.start, end: window.end }, timeZone);
    return {
      weekStart: range.start,
      weekEnd: range.end,
      totalMachines: totals[index] ?? 0,
    };
  });
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
          sku_id,
          sku_code,
          sku_name,
          SUM(CASE 
                WHEN scheduledFor >= ${window.currentStart}
                 AND scheduledFor < ${window.currentComparisonEnd}
                THEN count
                ELSE 0
              END) AS current_total,
          SUM(CASE 
                WHEN scheduledFor >= ${window.previousStart}
                 AND scheduledFor < ${window.previousComparisonEnd}
                THEN count
                ELSE 0
              END) AS previous_total
        FROM v_pick_entry_details
        WHERE companyId = ${companyId}
          AND scheduledFor IS NOT NULL
          AND scheduledFor >= ${window.previousStart}
          AND scheduledFor < ${window.currentComparisonEnd}
        GROUP BY sku_id, sku_code, sku_name
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
          machine_id,
          machine_code,
          machine_description,
          location_id,
          location_name,
          SUM(CASE 
                WHEN scheduledFor >= ${window.currentStart}
                 AND scheduledFor < ${window.currentComparisonEnd}
                THEN count
                ELSE 0
              END) AS current_total,
          SUM(CASE 
                WHEN scheduledFor >= ${window.previousStart}
                 AND scheduledFor < ${window.previousComparisonEnd}
                THEN count
                ELSE 0
              END) AS previous_total
        FROM v_pick_entry_details
        WHERE companyId = ${companyId}
          AND scheduledFor IS NOT NULL
          AND scheduledFor >= ${window.previousStart}
          AND scheduledFor < ${window.currentComparisonEnd}
        GROUP BY machine_id, machine_code, machine_description, location_id, location_name
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
          location_id,
          location_name,
          SUM(CASE 
                WHEN scheduledFor >= ${window.currentStart}
                 AND scheduledFor < ${window.currentComparisonEnd}
                THEN count
                ELSE 0
              END) AS current_total,
          SUM(CASE 
                WHEN scheduledFor >= ${window.previousStart}
                 AND scheduledFor < ${window.previousComparisonEnd}
                THEN count
                ELSE 0
              END) AS previous_total
        FROM v_pick_entry_details
        WHERE companyId = ${companyId}
          AND scheduledFor IS NOT NULL
          AND scheduledFor >= ${window.previousStart}
          AND scheduledFor < ${window.currentComparisonEnd}
        GROUP BY location_id, location_name
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
) {
  return prisma.$queryRaw<DashboardSkuComparisonRow[]>(
    Prisma.sql`
      SELECT *
      FROM (
        SELECT
          sku_id,
          SUM(CASE 
                WHEN scheduledFor >= ${window.currentStart}
                 AND scheduledFor < ${window.currentComparisonEnd}
                THEN count
                ELSE 0
              END) AS current_total,
          SUM(CASE 
                WHEN scheduledFor >= ${window.previousStart}
                 AND scheduledFor < ${window.previousComparisonEnd}
                THEN count
                ELSE 0
              END) AS previous_total
        FROM v_pick_entry_details
        WHERE companyId = ${companyId}
          AND scheduledFor IS NOT NULL
          AND scheduledFor >= ${window.previousStart}
          AND scheduledFor < ${window.currentComparisonEnd}
          AND sku_id IS NOT NULL
        GROUP BY sku_id
      ) AS sku_totals
      WHERE current_total > 0 OR previous_total > 0
      ORDER BY (current_total + previous_total) DESC, current_total DESC, sku_id ASC
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
              WHEN scheduledFor >= ${window.currentStart}
               AND scheduledFor < ${window.currentComparisonEnd}
              THEN count
              ELSE 0
            END) AS current_total,
        SUM(CASE 
              WHEN scheduledFor >= ${window.previousStart}
               AND scheduledFor < ${window.previousComparisonEnd}
              THEN count
              ELSE 0
            END) AS previous_total
      FROM v_pick_entry_details
      WHERE companyId = ${companyId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${window.previousStart}
        AND scheduledFor < ${window.currentComparisonEnd}
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
  const segments = segmentRows
    .map(mapDashboardSkuComparisonSegment)
    .filter((segment) => segment.currentTotal > 0 || segment.previousTotal > 0);

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
