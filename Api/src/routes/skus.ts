import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { isCompanyManager } from './helpers/authorization.js';
import { isValidTimezone } from '../lib/timezone.js';
import { AuthContext } from '../types/enums.js';
import { parseTimezoneQueryParam, resolveCompanyTimezone } from './helpers/timezone.js';
import { formatAppDate, formatAppExclusiveRange } from './helpers/app-dates.js';
import {
  ONE_DAY_MS,
  PERIOD_DAY_COUNTS,
  buildChartBuckets,
  buildChartRange,
  buildPercentageChange,
  buildPeriodRange,
  parseLocalDate,
  type PeriodBucket,
  type StatsPeriod,
} from './helpers/stats.js';

type SkuStatsPeriod = StatsPeriod;

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
  const persistTimezone = req.auth!.context === AuthContext.APP;
  const timeZone: string = await resolveCompanyTimezone(req.auth!.companyId, timezoneOverride, {
    persistIfMissing: persistTimezone,
  });

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

  const locationFilter = normalizeFilterValue(req.query.locationId);
  const machineFilter = normalizeFilterValue(req.query.machineId);

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
  const chartRange = buildChartRange(period, periodRange, timeZone, now);
  const dataEnd = new Date(Math.min(periodRange.end.getTime(), chartRange.end.getTime()));
  const elapsedMs = Math.max(0, Math.min(periodDurationMs, now.getTime() - periodStart.getTime()));

  const [chartData, locationRows, machineRows] = await Promise.all([
    buildSkuChartPoints(
      skuId,
      chartRange.start,
      chartRange.end,
      dataEnd,
      periodStart,
      periodEnd,
      req.auth!.companyId,
      timeZone,
      period,
      locationFilter,
      machineFilter,
    ),
    fetchSkuLocationOptions(skuId, req.auth!.companyId),
    fetchSkuMachineOptions(skuId, req.auth!.companyId),
  ]);

  const { points, totalItems, latestPeriodRowEndMs } = chartData;

  const coverageReferenceMs = Math.max(now.getTime(), latestPeriodRowEndMs ?? now.getTime());
  const coverageMs = Math.max(
    0,
    Math.min(periodDurationMs, coverageReferenceMs - periodStart.getTime()),
  );
  const previousWindowEnd = new Date(periodStart);
  const previousWindowStart = new Date(periodStart.getTime() - coverageMs);

  const previousTotal =
    coverageMs > 0
      ? await getSkuTotalPicks(
          skuId,
          previousWindowStart,
          previousWindowEnd,
          req.auth!.companyId,
          locationFilter,
          machineFilter,
        )
      : 0;

  const percentageChange =
    coverageMs > 0 ? buildPercentageChange(totalItems, previousTotal) : null;
  const bestMachine = await getSkuBestMachine(
    skuId,
    req.auth!.companyId,
    locationFilter,
    machineFilter,
  );
  const mostRecentPick = await getMostRecentPick(
    skuId,
    req.auth!.companyId,
    locationFilter,
    machineFilter,
  );

  const responseRange = formatAppExclusiveRange(
    { start: periodStart, end: periodEnd },
    timeZone,
  );
  const formattedNow = formatAppDate(now, timeZone);
  const formattedMostRecentPick = mostRecentPick
    ? {
        ...mostRecentPick,
        pickedAt: formatAppDate(mostRecentPick.pickedAt, timeZone),
      }
    : null;

  return res.json({
    generatedAt: new Date().toISOString(),
    timeZone,
    period,
    rangeStart: responseRange.start,
    rangeEnd: formattedNow,
    lookbackDays: periodDays,
    progress: {
      elapsedSeconds: Math.round(elapsedMs / 1000),
      periodSeconds: Math.round(periodDurationMs / 1000),
      ratio: periodDurationMs > 0 ? Number((elapsedMs / periodDurationMs).toFixed(3)) : 0,
    },
    percentageChange,
    bestMachine,
    points,
    mostRecentPick: formattedMostRecentPick,
    filters: {
      locationId: locationFilter,
      machineId: machineFilter,
    },
    locations: locationRows
      .filter(row => row.locationId)
      .map(row => ({
        id: row.locationId!,
        name: row.locationName ?? 'Location',
        totalItems: Number(row.machineCount ?? 0),
      })),
    machines: machineRows
      .filter(row => row.machineId)
      .map(row => ({
        id: row.machineId!,
        code: row.machineCode ?? 'Machine',
        description: row.machineDescription ?? row.machineCode ?? 'Machine',
        locationId: row.locationId ?? undefined,
        locationName: row.locationName ?? undefined,
        totalItems: Number(row.placementCount ?? 0),
      })),
  });
});

async function getMostRecentPick(
  skuId: string,
  companyId: string,
  locationFilter: string | null,
  machineFilter: string | null,
) {
  const machineFilters = buildMachineFilterSql(locationFilter, machineFilter);

  const result = await prisma.$queryRaw<Array<{
    scheduledFor: Date | null;
    locationName: string;
    runId: string;
  }>>(
    Prisma.sql`
      SELECT 
        scheduledFor,
        location_name AS locationName,
        runId
      FROM v_pick_entry_details
      WHERE sku_id = ${skuId}
        AND scheduledFor IS NOT NULL
        AND companyId = ${companyId}
        ${machineFilters}
      ORDER BY scheduledFor DESC
      LIMIT 1
    `
  );

  const [row] = result;
  if (!row || !row.scheduledFor) {
    return null;
  }

  return {
    pickedAt: row.scheduledFor,
    locationName: row.locationName || 'Unknown',
    runId: row.runId,
  };
}

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

type SkuLocationOptionRow = {
  locationId: string | null;
  locationName: string | null;
  machineCount: bigint | number | null;
};

type SkuMachineOptionRow = {
  machineId: string | null;
  machineCode: string | null;
  machineDescription: string | null;
  locationId: string | null;
  locationName: string | null;
  placementCount: bigint | number | null;
};

async function buildSkuChartPoints(
  skuId: string,
  chartStart: Date,
  chartEnd: Date,
  dataEnd: Date,
  periodStart: Date,
  periodEnd: Date,
  companyId: string,
  timeZone: string,
  period: SkuStatsPeriod,
  locationFilter: string | null,
  machineFilter: string | null,
) {
  const machineFilters = buildMachineFilterSql(locationFilter, machineFilter);

  const rows = await prisma.$queryRaw<Array<ChartRow>>(
    Prisma.sql`
      SELECT 
        DATE_FORMAT(CONVERT_TZ(scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS date,
        machine_id AS machineId,
        machine_code AS machineCode,
        machine_description AS machineName,
        SUM(count) AS totalPicked
      FROM v_pick_entry_details
      WHERE sku_id = ${skuId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${chartStart}
        AND scheduledFor < ${dataEnd}
        AND companyId = ${companyId}
        ${machineFilters}
      GROUP BY date, machine_id, machine_code, machine_description
      ORDER BY date ASC, machine_code ASC
    `,
  );

  const buckets = buildChartBuckets(period, chartStart, chartEnd, timeZone);

  const periodStartMs = periodStart.getTime();
  const periodEndMs = periodEnd.getTime();
  const bucketTotals = new Map<string, number>();
  const bucketMachines = new Map<
    string,
    Map<string, { machineCode: string; machineName: string | null; count: number }>
  >();
  let latestPeriodRowEndMs: number | null = null;
  let periodTotalItems = 0;

  for (const row of rows) {
    const rowDate = parseLocalDate(row.date, timeZone);
    const rowDateMs = rowDate.getTime();
    const rowEndMs = rowDateMs + ONE_DAY_MS;
    const rowCount = Number(row.totalPicked);

    if (rowEndMs > periodStartMs && rowDateMs < periodEndMs) {
      periodTotalItems += rowCount;
      const clampedRowEnd = Math.min(rowEndMs, periodEndMs);
      latestPeriodRowEndMs =
        latestPeriodRowEndMs === null
          ? clampedRowEnd
          : Math.max(latestPeriodRowEndMs, clampedRowEnd);
    }

    const bucket = buckets.find(b => rowDateMs >= b.startMs && rowDateMs < b.endMs);
    if (!bucket) {
      continue;
    }

    const machinesForBucket = bucketMachines.get(bucket.key) ?? new Map();
    const existing = machinesForBucket.get(row.machineId);

    machinesForBucket.set(row.machineId, {
      machineCode: row.machineCode,
      machineName: row.machineName,
      count: (existing?.count ?? 0) + rowCount,
    });

    bucketMachines.set(bucket.key, machinesForBucket);
    bucketTotals.set(bucket.key, (bucketTotals.get(bucket.key) ?? 0) + rowCount);
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

  return { points, totalItems: periodTotalItems, latestPeriodRowEndMs };
}

async function fetchSkuLocationOptions(skuId: string, companyId: string) {
  return prisma.$queryRaw<Array<SkuLocationOptionRow>>(
    Prisma.sql`
      SELECT 
        location_id AS locationId,
        location_name AS locationName,
        COUNT(DISTINCT machine_id) AS machineCount
      FROM v_pick_entry_details
      WHERE sku_id = ${skuId}
        AND companyId = ${companyId}
        AND location_id IS NOT NULL
      GROUP BY location_id, location_name
      ORDER BY location_name ASC
    `,
  );
}

async function fetchSkuMachineOptions(skuId: string, companyId: string) {
  return prisma.$queryRaw<Array<SkuMachineOptionRow>>(
    Prisma.sql`
      SELECT 
        machine_id AS machineId,
        machine_code AS machineCode,
        machine_description AS machineDescription,
        location_id AS locationId,
        location_name AS locationName,
        COUNT(*) AS placementCount
      FROM v_pick_entry_details
      WHERE sku_id = ${skuId}
        AND companyId = ${companyId}
      GROUP BY machine_id, machine_code, machine_description, location_id, location_name
      ORDER BY machine_code ASC
    `,
  );
}

async function getSkuTotalPicks(
  skuId: string,
  startDate: Date,
  endDate: Date,
  companyId: string,
  locationFilter: string | null,
  machineFilter: string | null,
) {
  const machineFilters = buildMachineFilterSql(locationFilter, machineFilter);

  const result = await prisma.$queryRaw<Array<{ totalPicked: bigint }>>(
    Prisma.sql`
      SELECT SUM(count) AS totalPicked
      FROM v_pick_entry_details
      WHERE sku_id = ${skuId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${startDate}
        AND scheduledFor < ${endDate}
        AND companyId = ${companyId}
        ${machineFilters}
    `,
  );

  return Number(result[0]?.totalPicked ?? 0);
}

async function getSkuBestMachine(
  skuId: string,
  companyId: string,
  locationFilter: string | null,
  machineFilter: string | null,
) {
  const machineFilters = buildMachineFilterSql(locationFilter, machineFilter);

  const result = await prisma.$queryRaw<Array<{
    machineId: string;
    machineCode: string;
    machineName: string | null;
    locationName: string | null;
    totalPicked: bigint;
  }>>(
    Prisma.sql`
      SELECT 
        machine_id AS machineId,
        machine_code AS machineCode,
        machine_description AS machineName,
        location_name AS locationName,
        SUM(count) AS totalPicked
      FROM v_pick_entry_details
      WHERE sku_id = ${skuId}
        AND companyId = ${companyId}
        ${machineFilters}
      GROUP BY machine_id, machine_code, machine_description, location_name
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
    locationName: row.locationName,
    totalPacks: Number(row.totalPicked),
  };
}

function buildMachineFilterSql(locationFilter: string | null, machineFilter: string | null) {
  if (locationFilter && machineFilter) {
    return Prisma.sql`AND location_id = ${locationFilter} AND machine_id = ${machineFilter}`;
  }
  if (locationFilter) {
    return Prisma.sql`AND location_id = ${locationFilter}`;
  }
  if (machineFilter) {
    return Prisma.sql`AND machine_id = ${machineFilter}`;
  }
  return Prisma.sql``;
}

function normalizeFilterValue(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export const skuRouter = router;
