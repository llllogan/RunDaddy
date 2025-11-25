import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { isValidTimezone } from '../lib/timezone.js';
import { AuthContext } from '../types/enums.js';
import { parseTimezoneQueryParam, resolveCompanyTimezone } from './helpers/timezone.js';
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

router.get('/:machineId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { machineId } = req.params;
  if (!machineId) {
    return res.status(400).json({ error: 'Machine ID is required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'User must belong to a company' });
  }

  const machine = await prisma.machine.findFirst({
    where: {
      id: machineId,
      companyId: req.auth.companyId,
    },
    include: {
      machineType: true,
      location: true,
    },
  });

  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  return res.json({
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
    location: machine.location
      ? {
          id: machine.location.id,
          name: machine.location.name,
          address: machine.location.address,
        }
      : null,
  });
});

router.get('/:machineId/stats', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { machineId } = req.params;
  if (!machineId) {
    return res.status(400).json({ error: 'Machine ID is required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'User must belong to a company' });
  }

  const timezoneOverride = parseTimezoneQueryParam(req.query.timezone);
  if (timezoneOverride && !isValidTimezone(timezoneOverride)) {
    return res.status(400).json({
      error: 'Invalid timezone supplied. Please use an IANA timezone like "America/Chicago".',
    });
  }

  const machine = await prisma.machine.findFirst({
    where: {
      id: machineId,
      companyId: req.auth.companyId,
    },
  });

  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  const now = new Date();
  const persistTimezone = req.auth.context === AuthContext.APP;
  const timeZone = await resolveCompanyTimezone(req.auth.companyId, timezoneOverride, {
    persistIfMissing: persistTimezone,
  });

  const periodQuery =
    typeof req.query.period === 'string' ? req.query.period.toLowerCase() : undefined;
  const period =
    periodQuery === 'week' || periodQuery === 'month' || periodQuery === 'quarter'
      ? (periodQuery as StatsPeriod)
      : 'week';

  const periodRange = buildPeriodRange(period, now, timeZone);
  const periodStart = periodRange.start;
  const periodEnd = periodRange.end;
  const periodDurationMs = periodEnd.getTime() - periodStart.getTime();
  const periodDays = PERIOD_DAY_COUNTS[period];

  const chartRange = buildChartRange(period, periodRange, timeZone, now);
  const dataEnd = new Date(Math.min(periodRange.end.getTime(), chartRange.end.getTime()));
  const elapsedMs = Math.max(0, Math.min(periodDurationMs, now.getTime() - periodStart.getTime()));

  const chartData = await buildMachineChartPoints(
    machineId,
    chartRange.start,
    chartRange.end,
    dataEnd,
    periodStart,
    periodEnd,
    req.auth.companyId,
    timeZone,
    period,
  );

  const { points, totalItems, latestPeriodRowEndMs } = chartData;

  const previousPeriodStart = new Date(periodStart.getTime() - periodDurationMs);
  const previousTotal = await getMachineTotalPicks(
    machineId,
    previousPeriodStart,
    periodStart,
    req.auth.companyId,
  );

  const percentageChange = buildAveragePercentageChange(totalItems, previousTotal, periodDays);

  const [bestSku, lastStocked] = await Promise.all([
    getMachineBestSku(machineId, req.auth.companyId, periodStart, periodEnd),
    getMachineLastStocked(machineId, req.auth.companyId),
  ]);

  const responseRange = formatAppExclusiveRange(
    { start: periodStart, end: periodEnd },
    timeZone,
  );
  const formattedNow = formatAppDate(now, timeZone);
  const formattedLastStocked = lastStocked
    ? {
        ...lastStocked,
        stockedAt: formatAppIsoDate(lastStocked.stockedAt),
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
    bestSku,
    lastStocked: formattedLastStocked,
    points,
  });
});

type MachineChartRow = {
  date: string;
  skuId: string;
  skuCode: string;
  skuName: string;
  totalPicked: bigint;
};

type MachineChartPoint = {
  date: string;
  totalItems: number;
  skus: Array<{
    skuId: string;
    skuCode: string;
    skuName: string;
    count: number;
  }>;
};

async function buildMachineChartPoints(
  machineId: string,
  chartStart: Date,
  chartEnd: Date,
  dataEnd: Date,
  periodStart: Date,
  periodEnd: Date,
  companyId: string,
  timeZone: string,
  period: StatsPeriod,
) {
  const rows = await prisma.$queryRaw<Array<MachineChartRow>>(
    Prisma.sql`
      SELECT 
        DATE_FORMAT(CONVERT_TZ(scheduledFor, 'UTC', ${timeZone}), '%Y-%m-%d') AS date,
        sku_id AS skuId,
        sku_code AS skuCode,
        sku_name AS skuName,
        SUM(count) AS totalPicked
      FROM v_pick_entry_details
      WHERE machine_id = ${machineId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${chartStart}
        AND scheduledFor < ${dataEnd}
        AND companyId = ${companyId}
      GROUP BY date, sku_id, sku_code, sku_name
      ORDER BY date ASC, sku_name ASC
    `,
  );

  const buckets = buildChartBuckets(period, chartStart, chartEnd, timeZone);

  const bucketTotals = new Map<string, number>();
  const bucketSkus = new Map<
    string,
    Map<string, { skuCode: string; skuName: string; count: number }>
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
    }

    const bucket = buckets.find(b => rowDateMs >= b.startMs && rowDateMs < b.endMs);
    if (!bucket) {
      continue;
    }

    const skusForBucket = bucketSkus.get(bucket.key) ?? new Map();
    const existing = skusForBucket.get(row.skuId);

    skusForBucket.set(row.skuId, {
      skuCode: row.skuCode,
      skuName: row.skuName,
      count: (existing?.count ?? 0) + rowCount,
    });

    bucketSkus.set(bucket.key, skusForBucket);
    bucketTotals.set(bucket.key, (bucketTotals.get(bucket.key) ?? 0) + rowCount);
  }

  const points: MachineChartPoint[] = buckets.map(bucket => {
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
      skus,
    };
  });

  return { points, totalItems: periodTotalItems, latestPeriodRowEndMs };
}

async function getMachineTotalPicks(
  machineId: string,
  startDate: Date,
  endDate: Date,
  companyId: string,
) {
  const result = await prisma.$queryRaw<Array<{ totalPicked: bigint }>>(
    Prisma.sql`
      SELECT SUM(count) AS totalPicked
      FROM v_pick_entry_details
      WHERE machine_id = ${machineId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${startDate}
        AND scheduledFor < ${endDate}
        AND companyId = ${companyId}
    `,
  );

  return Number(result[0]?.totalPicked ?? 0);
}

async function getMachineBestSku(
  machineId: string,
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
      WHERE machine_id = ${machineId}
        AND scheduledFor IS NOT NULL
        AND scheduledFor >= ${periodStart}
        AND scheduledFor < ${periodEnd}
        AND companyId = ${companyId}
      GROUP BY sku_id, sku_code, sku_name
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

async function getMachineLastStocked(machineId: string, companyId: string) {
  const result = await prisma.$queryRaw<Array<{
    scheduledFor: Date | null;
    runId: string;
  }>>(
    Prisma.sql`
      SELECT 
        scheduledFor,
        runId
      FROM v_pick_entry_details
      WHERE machine_id = ${machineId}
        AND scheduledFor IS NOT NULL
        AND companyId = ${companyId}
      ORDER BY scheduledFor DESC
      LIMIT 1
    `,
  );

  const [row] = result;
  if (!row) {
    return null;
  }

  return {
    stockedAt: row.scheduledFor ?? new Date(),
    runId: row.runId,
  };
}

export const machinesRouter = router;
