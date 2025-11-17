import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { isValidTimezone } from '../lib/timezone.js';
import { parseTimezoneQueryParam, resolveCompanyTimezone } from './helpers/timezone.js';
import {
  ONE_DAY_MS,
  PERIOD_DAY_COUNTS,
  buildChartBuckets,
  buildChartRange,
  buildPercentageChange,
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

  const timezoneOverride = parseTimezoneQueryParam(req.query.timezone);
  if (timezoneOverride && !isValidTimezone(timezoneOverride)) {
    return res.status(400).json({
      error: 'Invalid timezone supplied. Please use an IANA timezone like "America/Chicago".',
    });
  }

  const now = new Date();
  const timeZone = await resolveCompanyTimezone(req.auth.companyId, timezoneOverride);

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

  const chartRange = buildChartRange(period, periodRange, timeZone);
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

  const coverageReferenceMs = Math.max(now.getTime(), latestPeriodRowEndMs ?? now.getTime());
  const coverageMs = Math.max(
    0,
    Math.min(periodDurationMs, coverageReferenceMs - periodStart.getTime()),
  );
  const previousWindowEnd = new Date(periodStart);
  const previousWindowStart = new Date(periodStart.getTime() - coverageMs);

  const previousTotal =
    coverageMs > 0
      ? await getLocationTotalPicks(
          locationId,
          previousWindowStart,
          previousWindowEnd,
          req.auth.companyId,
        )
      : 0;

  const percentageChange =
    coverageMs > 0 ? buildPercentageChange(totalItems, previousTotal) : null;

  const [bestMachine, bestSku, lastPacked] = await Promise.all([
    getLocationBestMachine(locationId, req.auth.companyId, periodStart, periodEnd),
    getLocationBestSku(locationId, req.auth.companyId, periodStart, periodEnd),
    getLocationLastPacked(locationId, req.auth.companyId),
  ]);

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
    lastPacked,
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
        DATE_FORMAT(CONVERT_TZ(r.scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS date,
        mach.id AS machineId,
        mach.code AS machineCode,
        mach.description AS machineDescription,
        sku.id AS skuId,
        sku.code AS skuCode,
        sku.name AS skuName,
        SUM(pe.count) AS totalPicked
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN SKU sku ON sku.id = ci.skuId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      JOIN Location loc ON loc.id = mach.locationId
      JOIN Run r ON r.id = pe.runId
      WHERE loc.id = ${locationId}
        AND r.scheduledFor IS NOT NULL
        AND r.scheduledFor >= ${chartStart}
        AND r.scheduledFor < ${dataEnd}
        AND r.companyId = ${companyId}
      GROUP BY date, mach.id, mach.code, mach.description, sku.id, sku.code, sku.name
      ORDER BY date ASC, mach.code ASC, sku.name ASC
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
      SELECT SUM(pe.count) AS totalPicked
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      JOIN Location loc ON loc.id = mach.locationId
      JOIN Run r ON r.id = pe.runId
      WHERE loc.id = ${locationId}
        AND r.scheduledFor IS NOT NULL
        AND r.scheduledFor >= ${startDate}
        AND r.scheduledFor < ${endDate}
        AND r.companyId = ${companyId}
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
        mach.id AS machineId,
        mach.code AS machineCode,
        mach.description AS machineDescription,
        SUM(pe.count) AS totalPicked
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      JOIN Location loc ON loc.id = mach.locationId
      JOIN Run r ON r.id = pe.runId
      WHERE loc.id = ${locationId}
        AND r.scheduledFor IS NOT NULL
        AND r.scheduledFor >= ${periodStart}
        AND r.scheduledFor < ${periodEnd}
        AND r.companyId = ${companyId}
      GROUP BY mach.id, mach.code, mach.description
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
        sku.id AS skuId,
        sku.code AS skuCode,
        sku.name AS skuName,
        sku.type AS skuType,
        SUM(pe.count) AS totalPicked
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN SKU sku ON sku.id = ci.skuId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      JOIN Location loc ON loc.id = mach.locationId
      JOIN Run r ON r.id = pe.runId
      WHERE loc.id = ${locationId}
        AND r.scheduledFor IS NOT NULL
        AND r.scheduledFor >= ${periodStart}
        AND r.scheduledFor < ${periodEnd}
        AND r.companyId = ${companyId}
      GROUP BY sku.id, sku.code, sku.name, sku.type
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
        r.scheduledFor,
        r.id AS runId,
        mach.id AS machineId,
        mach.code AS machineCode,
        mach.description AS machineDescription
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      JOIN Location loc ON loc.id = mach.locationId
      JOIN Run r ON r.id = pe.runId
      WHERE loc.id = ${locationId}
        AND r.scheduledFor IS NOT NULL
        AND r.companyId = ${companyId}
      ORDER BY r.scheduledFor DESC
      LIMIT 1
    `,
  );

  const [row] = result;
  if (!row || !row.scheduledFor) {
    return null;
  }
  return {
    pickedAt: row.scheduledFor.toISOString(),
    runId: row.runId,
    machineId: row.machineId,
    machineCode: row.machineCode,
    machineName: row.machineDescription,
  };
}

export const locationsRouter = router;
