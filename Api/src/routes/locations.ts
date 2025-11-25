import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';

import { AuthContext } from '../types/enums.js';
import { resolveCompanyTimezone } from './helpers/timezone.js';
import { formatAppDate, formatAppExclusiveRange, formatAppIsoDate } from './helpers/app-dates.js';
import {
  ONE_DAY_MS,
  PERIOD_DAY_COUNTS,
  buildChartBuckets,
  buildChartRange,
  buildAveragePercentageChange,
  buildPeriodRange,
  parseLocalDate,
  type StatsPeriod,
} from './helpers/stats.js';

const router = Router();

router.use(authenticate);

router.get('/:locationId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { locationId } = req.params;
  if (!locationId) {
    return res.status(400).json({ error: 'Location ID is required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'User must belong to a company' });
  }

  const location = await prisma.location.findFirst({
    where: {
      id: locationId,
      companyId: req.auth.companyId,
    },
  });

  if (!location) {
    return res.status(404).json({ error: 'Location not found' });
  }

  const machines = await prisma.machine.findMany({
    where: {
      locationId,
      companyId: req.auth.companyId,
    },
    include: {
      machineType: true,
    },
    orderBy: {
      code: 'asc',
    },
  });

  return res.json({
    id: location.id,
    name: location.name,
    address: location.address,
    machines: machines.map(machine => ({
      id: machine.id,
      code: machine.code,
      description: machine.description,
      machineType: machine.machineType
        ? {
            id: machine.machineType.id,
            name: machine.machineType.name,
            description: machine.machineType.description,
          }
        : null,
    })),
  });
});

router.get('/:locationId/stats', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { locationId } = req.params;
  if (!locationId) {
    return res.status(400).json({ error: 'Location ID is required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'User must belong to a company' });
  }

  const location = await prisma.location.findFirst({
    where: {
      id: locationId,
      companyId: req.auth.companyId,
    },
  });

  if (!location) {
    return res.status(404).json({ error: 'Location not found' });
  }



  const now = new Date();
  const timeZone = await resolveCompanyTimezone(req.auth.companyId);

  const periodQuery =
    typeof req.query.period === 'string' ? req.query.period.toLowerCase() : undefined;
  const period: StatsPeriod =
    periodQuery === 'week' || periodQuery === 'month' || periodQuery === 'quarter'
      ? periodQuery
      : 'week';

  const periodRange = buildPeriodRange(period, now, timeZone);
  const periodStart = periodRange.start;
  const periodEnd = periodRange.end;
  const periodDurationMs = periodEnd.getTime() - periodStart.getTime();
  const periodDays = PERIOD_DAY_COUNTS[period];

  const chartRange = buildChartRange(period, periodRange, timeZone, now);
  const dataEnd = new Date(Math.min(periodRange.end.getTime(), chartRange.end.getTime()));
  const elapsedMs = Math.max(0, Math.min(periodDurationMs, now.getTime() - periodStart.getTime()));

  const chartData = await buildLocationChartPoints(
    locationId,
    chartRange.start,
    chartRange.end,
    dataEnd,
    periodStart,
    periodEnd,
    req.auth.companyId,
    timeZone,
    period,
  );

  const { points, totalItems, latestPeriodRowEndMs, machineSalesShare } = chartData;

  const previousPeriodStart = new Date(periodStart.getTime() - periodDurationMs);
  const previousTotal = await getLocationTotalPicks(
    locationId,
    previousPeriodStart,
    periodStart,
    req.auth.companyId,
  );

  const percentageChange = buildAveragePercentageChange(totalItems, previousTotal, periodDays);

  const [bestMachine, bestSku, lastPacked] = await Promise.all([
    getLocationBestMachine(locationId, req.auth.companyId, periodStart, periodEnd),
    getLocationBestSku(locationId, req.auth.companyId, periodStart, periodEnd),
    getLocationLastPacked(locationId, req.auth.companyId),
  ]);

  const responseRange = formatAppExclusiveRange(
    { start: periodStart, end: periodEnd },
    timeZone,
  );
  const formattedNow = formatAppDate(now, timeZone);
  const formattedLastPacked = lastPacked
    ? {
        ...lastPacked,
        pickedAt: formatAppIsoDate(lastPacked.pickedAt),
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
    lastPacked: formattedLastPacked,
    bestMachine,
    bestSku,
    machineSalesShare,
    points,
  });
});

type LocationChartRow = {
  date: string;
  machineId: string;
  machineCode: string;
  machineDescription: string | null;
  skuId: string;
  skuCode: string;
  skuName: string;
  totalPicked: bigint;
};

type LocationChartPoint = {
  date: string;
  totalItems: number;
  machines: Array<{
    machineId: string;
    machineCode: string;
    machineName: string | null;
    count: number;
  }>;
  skus: Array<{
    skuId: string;
    skuCode: string;
    skuName: string;
    count: number;
  }>;
};

type LocationMachineSalesShare = {
  machineId: string;
  machineCode: string;
  machineName: string | null;
  count: number;
  percentage: number;
};

async function buildLocationChartPoints(
  locationId: string,
  chartStart: Date,
  chartEnd: Date,
  dataEnd: Date,
  periodStart: Date,
  periodEnd: Date,
  companyId: string,
  timeZone: string,
  period: StatsPeriod,
) {
  const rows = await prisma.$queryRaw<Array<LocationChartRow>>(
    Prisma.sql`
      SELECT 
        DATE_FORMAT(CONVERT_TZ(scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS date,
        machine_id AS machineId,
        machine_code AS machineCode,
        machine_description AS machineDescription,
        sku_id AS skuId,
        sku_code AS skuCode,
        sku_name AS skuName,
        SUM(count) AS totalPicked
      FROM v_pick_entry_details
      WHERE location_id = ${locationId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${chartStart}
        AND scheduledFor < ${dataEnd}
        AND companyId = ${companyId}
      GROUP BY date, machine_id, machine_code, machine_description, sku_id, sku_code, sku_name
      ORDER BY date ASC, machine_code ASC, sku_name ASC
    `,
  );

  const buckets = buildChartBuckets(period, chartStart, chartEnd, timeZone);

  const bucketTotals = new Map<string, number>();
  const bucketMachines = new Map<
    string,
    Map<string, { machineCode: string; machineName: string | null; count: number }>
  >();
  const bucketSkus = new Map<
    string,
    Map<string, { skuCode: string; skuName: string; count: number }>
  >();
  const machinePeriodTotals = new Map<
    string,
    { machineCode: string; machineName: string | null; count: number }
  >();
  const periodStartMs = periodStart.getTime();
  const periodEndMs = periodEnd.getTime();
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
      const existingMachineTotals = machinePeriodTotals.get(row.machineId) ?? {
        machineCode: row.machineCode,
        machineName: row.machineDescription,
        count: 0,
      };
      machinePeriodTotals.set(row.machineId, {
        machineCode: existingMachineTotals.machineCode,
        machineName: existingMachineTotals.machineName,
        count: existingMachineTotals.count + rowCount,
      });
    }

    const bucket = buckets.find(b => rowDateMs >= b.startMs && rowDateMs < b.endMs);
    if (!bucket) {
      continue;
    }

    const machinesForBucket = bucketMachines.get(bucket.key) ?? new Map();
    const existingMachine = machinesForBucket.get(row.machineId);
    machinesForBucket.set(row.machineId, {
      machineCode: row.machineCode,
      machineName: row.machineDescription,
      count: (existingMachine?.count ?? 0) + rowCount,
    });
    bucketMachines.set(bucket.key, machinesForBucket);

    const skusForBucket = bucketSkus.get(bucket.key) ?? new Map();
    const existingSku = skusForBucket.get(row.skuId);
    skusForBucket.set(row.skuId, {
      skuCode: row.skuCode,
      skuName: row.skuName,
      count: (existingSku?.count ?? 0) + rowCount,
    });
    bucketSkus.set(bucket.key, skusForBucket);

    bucketTotals.set(bucket.key, (bucketTotals.get(bucket.key) ?? 0) + rowCount);
  }

  const points: LocationChartPoint[] = buckets.map(bucket => {
    const machinesForBucket = bucketMachines.get(bucket.key);
    const machines = machinesForBucket
      ? Array.from(machinesForBucket.entries()).map(([machineId, machineData]) => ({
          machineId,
          machineCode: machineData.machineCode,
          machineName: machineData.machineName,
          count: machineData.count,
        }))
      : [];

    const skusForBucket = bucketSkus.get(bucket.key);
    const skus = skusForBucket
      ? Array.from(skusForBucket.entries()).map(([skuId, skuData]) => ({
          skuId,
          skuCode: skuData.skuCode,
          skuName: skuData.skuName,
          count: skuData.count,
        }))
      : [];

    const totalItems = bucketTotals.get(bucket.key) ?? 0;
    return {
      date: bucket.label,
      totalItems,
      machines,
      skus,
    };
  });

  const machineSalesShare: LocationMachineSalesShare[] =
    periodTotalItems > 0
      ? Array.from(machinePeriodTotals.entries())
          .map(([machineId, machineData]) => ({
            machineId,
            machineCode: machineData.machineCode,
            machineName: machineData.machineName,
            count: machineData.count,
            percentage: Number(((machineData.count / periodTotalItems) * 100).toFixed(1)),
          }))
          .sort((a, b) => b.count - a.count)
      : [];

  return { points, totalItems: periodTotalItems, latestPeriodRowEndMs, machineSalesShare };
}

async function getLocationTotalPicks(
  locationId: string,
  startDate: Date,
  endDate: Date,
  companyId: string,
) {
  const result = await prisma.$queryRaw<Array<{ totalPicked: bigint }>>(
    Prisma.sql`
      SELECT SUM(count) AS totalPicked
      FROM v_pick_entry_details
      WHERE location_id = ${locationId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${startDate}
        AND scheduledFor < ${endDate}
        AND companyId = ${companyId}
    `,
  );

  return Number(result[0]?.totalPicked ?? 0);
}

async function getLocationBestMachine(
  locationId: string,
  companyId: string,
  periodStart: Date,
  periodEnd: Date,
) {
  const result = await prisma.$queryRaw<Array<{
    machineId: string;
    machineCode: string;
    machineDescription: string | null;
    totalPicked: bigint;
  }>>(
    Prisma.sql`
      SELECT 
        machine_id AS machineId,
        machine_code AS machineCode,
        machine_description AS machineDescription,
        SUM(count) AS totalPicked
      FROM v_pick_entry_details
      WHERE location_id = ${locationId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${periodStart}
        AND scheduledFor < ${periodEnd}
        AND companyId = ${companyId}
      GROUP BY machine_id, machine_code, machine_description
      ORDER BY totalPicked DESC
      LIMIT 1
    `,
  );

  const [row] = result;
  if (!row) {
    return null;
  }
  return {
    machineId: row.machineId,
    machineCode: row.machineCode,
    machineName: row.machineDescription,
    totalPacks: Number(row.totalPicked),
  };
}

async function getLocationBestSku(
  locationId: string,
  companyId: string,
  periodStart: Date,
  periodEnd: Date,
) {
  const result = await prisma.$queryRaw<Array<{
    skuId: string;
    skuCode: string;
    skuName: string;
    skuType: string;
    totalPicked: bigint;
  }>>(
    Prisma.sql`
      SELECT 
        sku_id AS skuId,
        sku_code AS skuCode,
        sku_name AS skuName,
        sku_type AS skuType,
        SUM(count) AS totalPicked
      FROM v_pick_entry_details
      WHERE location_id = ${locationId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${periodStart}
        AND scheduledFor < ${periodEnd}
        AND companyId = ${companyId}
      GROUP BY sku_id, sku_code, sku_name, sku_type
      ORDER BY totalPicked DESC
      LIMIT 1
    `,
  );

  const [row] = result;
  if (!row) {
    return null;
  }
  return {
    skuId: row.skuId,
    skuCode: row.skuCode,
    skuName: row.skuName,
    skuType: row.skuType,
    totalPacks: Number(row.totalPicked),
  };
}

async function getLocationLastPacked(locationId: string, companyId: string) {
  const result = await prisma.$queryRaw<Array<{
    scheduledFor: Date | null;
    runId: string;
    machineId: string | null;
    machineCode: string | null;
    machineDescription: string | null;
  }>>(
    Prisma.sql`
      SELECT 
        scheduledFor,
        runId,
        machine_id AS machineId,
        machine_code AS machineCode,
        machine_description AS machineDescription
      FROM v_pick_entry_details
      WHERE location_id = ${locationId}
        AND scheduledFor IS NOT NULL
        AND companyId = ${companyId}
      ORDER BY scheduledFor DESC
      LIMIT 1
    `,
  );

  const [row] = result;
  if (!row || !row.scheduledFor) {
    return null;
  }
  return {
    pickedAt: row.scheduledFor,
    runId: row.runId,
    machineId: row.machineId,
    machineCode: row.machineCode,
    machineName: row.machineDescription,
  };
}

export const locationsRouter = router;
