import { Router } from 'express';
import { Prisma, type SKU } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { isCompanyManager } from './helpers/authorization.js';

import { AuthContext } from '../types/enums.js';
import { resolveCompanyTimezone } from './helpers/timezone.js';
import { formatAppDate, formatAppExclusiveRange, formatAppIsoDate } from './helpers/app-dates.js';
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
const HEX_COLOUR_REGEX = /^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/;

router.use(authenticate);

router.get('/cold-chest/count', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const companyId = req.auth.companyId;
  if (!companyId) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const count = await prisma.sKU.count({
    where: {
      ...buildSkuCompanyWhere(companyId),
      isFreshOrFrozen: true,
    },
  });

  return res.json({ count });
});

router.get('/cold-chest', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const companyId = req.auth.companyId;
  if (!companyId) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const skus = await prisma.sKU.findMany({
    where: {
      ...buildSkuCompanyWhere(companyId),
      isFreshOrFrozen: true,
    },
    orderBy: {
      code: 'asc',
    },
    select: {
      id: true,
      code: true,
      name: true,
      type: true,
      category: true,
      weight: true,
      labelColour: true,
      countNeededPointer: true,
      isFreshOrFrozen: true,
      expiryDays: true,
    },
  });

  return res.json(
    skus.map((sku) => ({
      id: sku.id,
      code: sku.code,
      name: sku.name,
      type: sku.type,
      category: sku.category,
      weight: sku.weight,
      labelColour: sku.labelColour,
      countNeededPointer: sku.countNeededPointer,
      isFreshOrFrozen: sku.isFreshOrFrozen,
      expiryDays: sku.expiryDays,
    })),
  );
});

router.get('/missing-weight/count', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const companyId = req.auth.companyId;
  if (!companyId) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const count = await prisma.sKU.count({
    where: {
      ...buildSkuCompanyWhere(companyId),
      weight: null,
    },
  });

  return res.json({ count });
});

// Update SKU isFreshOrFrozen field
router.patch('/:skuId/fresh-or-frozen', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  const { isFreshOrFrozen } = req.body;
  if (typeof isFreshOrFrozen !== 'boolean') {
    return res.status(400).json({ error: 'isFreshOrFrozen must be a boolean' });
  }

  const skuResult = await getSkuForCompany(skuId, req.auth.companyId);
  if (skuResult.status === 'not_found') {
    return res.status(404).json({ error: 'SKU not found' });
  }
  if (skuResult.status === 'forbidden') {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  // Only managers can update SKU fields
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKU' });
  }

  const updatedSku = await prisma.sKU.update({
    where: { id: skuId },
    data: { isFreshOrFrozen },
  });

  return res.json({
    id: updatedSku.id,
    code: updatedSku.code,
    name: updatedSku.name,
    type: updatedSku.type,
    labelColour: updatedSku.labelColour,
    isFreshOrFrozen: updatedSku.isFreshOrFrozen,
    expiryDays: updatedSku.expiryDays,
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

  const skuResult = await getSkuForCompany(skuId, req.auth.companyId);
  if (skuResult.status === 'not_found') {
    return res.status(404).json({ error: 'SKU not found' });
  }
  if (skuResult.status === 'forbidden') {
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
    labelColour: updatedSku.labelColour,
    countNeededPointer: updatedSku.countNeededPointer,
    expiryDays: updatedSku.expiryDays,
  });
});

// Update SKU expiryDays field
router.patch('/:skuId/expiry-days', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  const { expiryDays } = req.body;
  const parsedExpiryDays = Number(expiryDays);
  if (!Number.isFinite(parsedExpiryDays) || !Number.isInteger(parsedExpiryDays) || parsedExpiryDays < 0) {
    return res.status(400).json({ error: 'expiryDays must be a non-negative integer' });
  }

  const skuResult = await getSkuForCompany(skuId, req.auth.companyId);
  if (skuResult.status === 'not_found') {
    return res.status(404).json({ error: 'SKU not found' });
  }
  if (skuResult.status === 'forbidden') {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKU' });
  }

  const companyId = req.auth.companyId as string;
  const timeZone = await resolveCompanyTimezone(companyId);
  const lookbackStart = new Date();
  lookbackStart.setMonth(lookbackStart.getMonth() - 3);

  const updatedSku = await prisma.sKU.update({
    where: { id: skuId },
    data: { expiryDays: parsedExpiryDays },
  });

  if (updatedSku.expiryDays <= 0) {
    await prisma.$executeRaw(
      Prisma.sql`
        UPDATE PickEntry pe
          INNER JOIN Run r ON r.id = pe.runId
          INNER JOIN CoilItem ci ON ci.id = pe.coilItemId
        SET pe.expiryDate = NULL
        WHERE r.companyId = ${companyId}
          AND ci.skuId = ${skuId}
          AND r.scheduledFor IS NOT NULL
          AND r.scheduledFor >= ${lookbackStart};
      `,
    );
  } else {
    const expiryOffsetDays = Math.max(0, Math.floor(updatedSku.expiryDays) - 1);
    await prisma.$executeRaw(
      Prisma.sql`
        UPDATE PickEntry pe
          INNER JOIN Run r ON r.id = pe.runId
          INNER JOIN CoilItem ci ON ci.id = pe.coilItemId
        SET pe.expiryDate = DATE_FORMAT(
          DATE_ADD(CONVERT_TZ(r.scheduledFor, 'UTC', ${timeZone}), INTERVAL ${expiryOffsetDays} DAY),
          '%Y-%m-%d'
        )
        WHERE r.companyId = ${companyId}
          AND ci.skuId = ${skuId}
          AND r.scheduledFor IS NOT NULL
          AND r.scheduledFor >= ${lookbackStart};
      `,
    );
  }

  return res.json({
    id: updatedSku.id,
    code: updatedSku.code,
    name: updatedSku.name,
    type: updatedSku.type,
    labelColour: updatedSku.labelColour,
    countNeededPointer: updatedSku.countNeededPointer,
    isFreshOrFrozen: updatedSku.isFreshOrFrozen,
    expiryDays: updatedSku.expiryDays,
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

  const skuResult = await getSkuForCompany(skuId, req.auth.companyId);
  if (skuResult.status === 'not_found') {
    return res.status(404).json({ error: 'SKU not found' });
  }
  if (skuResult.status === 'forbidden') {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  return res.json({
    id: skuResult.sku.id,
    code: skuResult.sku.code,
    name: skuResult.sku.name,
    type: skuResult.sku.type,
    category: skuResult.sku.category,
    weight: skuResult.sku.weight,
    isFreshOrFrozen: skuResult.sku.isFreshOrFrozen,
    labelColour: skuResult.sku.labelColour,
    countNeededPointer: skuResult.sku.countNeededPointer,
    expiryDays: skuResult.sku.expiryDays,
  });
});

// Update SKU weight
router.patch('/:skuId/weight', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  const { weight } = req.body;
  if (weight !== null && weight !== undefined) {
    const parsedWeight = Number(weight);
    if (Number.isNaN(parsedWeight) || !Number.isFinite(parsedWeight) || parsedWeight < 0) {
      return res
        .status(400)
        .json({ error: 'weight must be a non-negative number or null to clear it' });
    }
  }

  const skuResult = await getSkuForCompany(skuId, req.auth.companyId);
  if (skuResult.status === 'not_found') {
    return res.status(404).json({ error: 'SKU not found' });
  }
  if (skuResult.status === 'forbidden') {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKU' });
  }

  const parsedWeight =
    weight === null || weight === undefined ? null : Number(weight);
  const updatedSku = await prisma.sKU.update({
    where: { id: skuId },
    data: { weight: parsedWeight },
  });

  return res.json({
    id: updatedSku.id,
    code: updatedSku.code,
    name: updatedSku.name,
    type: updatedSku.type,
    category: updatedSku.category,
    weight: updatedSku.weight,
    labelColour: updatedSku.labelColour,
    countNeededPointer: updatedSku.countNeededPointer,
    isFreshOrFrozen: updatedSku.isFreshOrFrozen,
    expiryDays: updatedSku.expiryDays,
  });
});

// Update SKU label colour
router.patch('/:skuId/label-colour', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  const { labelColour } = req.body;
  if (labelColour === undefined) {
    return res.status(400).json({ error: 'labelColour is required (set null to clear)' });
  }
  if (labelColour !== null && typeof labelColour !== 'string') {
    return res.status(400).json({ error: 'labelColour must be a hex colour string or null' });
  }

  let normalizedLabelColour: string | null = null;
  if (typeof labelColour === 'string') {
    const trimmed = labelColour.trim();
    const hexValue = trimmed.startsWith('#') ? trimmed.slice(1) : trimmed;

    if (!HEX_COLOUR_REGEX.test(hexValue)) {
      return res.status(400).json({
        error: 'labelColour must be a 6 or 8 character hex string (e.g. #FFD60AFF)',
      });
    }

    const paddedHex = hexValue.length === 6 ? `${hexValue}FF` : hexValue;
    normalizedLabelColour = `#${paddedHex.toUpperCase()}`;
  }

  const skuResult = await getSkuForCompany(skuId, req.auth.companyId);
  if (skuResult.status === 'not_found') {
    return res.status(404).json({ error: 'SKU not found' });
  }
  if (skuResult.status === 'forbidden') {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKU' });
  }

  const updatedSku = await prisma.sKU.update({
    where: { id: skuId },
    data: { labelColour: normalizedLabelColour },
  });

  return res.json({
    id: updatedSku.id,
    code: updatedSku.code,
    name: updatedSku.name,
    type: updatedSku.type,
    category: updatedSku.category,
    weight: updatedSku.weight,
    labelColour: updatedSku.labelColour,
    countNeededPointer: updatedSku.countNeededPointer,
    isFreshOrFrozen: updatedSku.isFreshOrFrozen,
    expiryDays: updatedSku.expiryDays,
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

  if (!req.auth!.companyId) {
    return res.status(403).json({ error: 'User must belong to a company' });
  }

  const now = new Date();
  const timeZone: string = await resolveCompanyTimezone(req.auth!.companyId);

  const skuResult = await getSkuForCompany(skuId, req.auth.companyId);
  if (skuResult.status === 'not_found') {
    return res.status(404).json({ error: 'SKU not found' });
  }
  if (skuResult.status === 'forbidden') {
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
  const previousPeriodStart = new Date(periodStart.getTime() - periodDurationMs);
  const previousPeriodEnd = periodStart;

  const [chartData, previousPeriodData, locationRows, machineRows] = await Promise.all([
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
    buildSkuChartPoints(
      skuId,
      previousPeriodStart,
      previousPeriodEnd,
      previousPeriodEnd,
      previousPeriodStart,
      previousPeriodEnd,
      req.auth!.companyId,
      timeZone,
      period,
      locationFilter,
      machineFilter,
    ),
    fetchSkuLocationOptions(skuId, req.auth!.companyId),
    fetchSkuMachineOptions(skuId, req.auth!.companyId),
  ]);

  const {
    points,
    totalItems: currentTotal,
    periodPositiveBucketCount: currentBucketCount,
    periodBucketSummaries: currentBucketSummaries,
  } = chartData;
  const {
    totalItems: previousTotal,
    periodPositiveBucketCount: previousBucketCount,
    periodBucketSummaries: previousBucketSummaries,
  } = previousPeriodData;

  const currentAverage = currentBucketCount > 0 ? currentTotal / currentBucketCount : currentTotal;
  const previousAverage =
    previousBucketCount > 0 ? previousTotal / previousBucketCount : previousTotal;

  const percentageChange = buildPercentageChange(currentAverage, previousAverage);
  const [bestMachine, mostRecentPick, firstSeen] = await Promise.all([
    getSkuBestMachine(skuId, req.auth!.companyId, locationFilter, machineFilter),
    getMostRecentPick(skuId, req.auth!.companyId, locationFilter, machineFilter),
    getSkuFirstSeen(skuId, req.auth!.companyId),
  ]);

  const responseRange = formatAppExclusiveRange(
    { start: periodStart, end: periodEnd },
    timeZone,
  );
  const formattedNow = formatAppDate(now, timeZone);
  const formattedMostRecentPick = mostRecentPick
    ? {
        ...mostRecentPick,
        pickedAt: formatAppIsoDate(mostRecentPick.pickedAt),
      }
    : null;
  const formattedFirstSeen = firstSeen ? formatAppIsoDate(firstSeen) : null;

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
    firstSeen: formattedFirstSeen,
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

async function getSkuFirstSeen(skuId: string, companyId: string) {
  const result = await prisma.$queryRaw<Array<{
    firstSeenAt: Date | null;
  }>>(
    Prisma.sql`
      SELECT 
        scheduledFor AS firstSeenAt
      FROM v_pick_entry_details
      WHERE sku_id = ${skuId}
        AND scheduledFor IS NOT NULL
        AND companyId = ${companyId}
      ORDER BY scheduledFor ASC
      LIMIT 1
    `
  );

  const [row] = result;
  return row?.firstSeenAt ?? null;
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
  const periodBucketTotals = new Map<string, number>();
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

    if (rowEndMs > periodStartMs && rowDateMs < periodEndMs) {
      periodBucketTotals.set(bucket.key, (periodBucketTotals.get(bucket.key) ?? 0) + rowCount);
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

  const isBucketInPeriod = (bucket: PeriodBucket) => {
    if (period === 'month') {
      const anchorMs = bucket.endMs - ONE_DAY_MS;
      return anchorMs >= periodStartMs && anchorMs < periodEndMs;
    }
    return bucket.startMs >= periodStartMs && bucket.startMs < periodEndMs;
  };

  const periodBucketSummaries = buckets.map(bucket => ({
    label: bucket.label,
    total: periodBucketTotals.get(bucket.key) ?? 0,
    isInPeriod: isBucketInPeriod(bucket),
  }));
  const periodBucketCount = periodBucketSummaries.filter(
    bucket => bucket.isInPeriod && bucket.total > 0,
  ).length;

  return {
    points,
    totalItems: periodTotalItems,
    latestPeriodRowEndMs,
    periodPositiveBucketCount: periodBucketCount,
    periodBucketSummaries,
  };
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

type SkuAccessResult =
  | { status: 'ok'; sku: SKU }
  | { status: 'not_found' }
  | { status: 'forbidden' };

async function getSkuForCompany(skuId: string, companyId: string | null): Promise<SkuAccessResult> {
  if (!companyId) {
    return { status: 'forbidden' };
  }

  const sku = await prisma.sKU.findUnique({
    where: { id: skuId },
  });

  if (!sku) {
    return { status: 'not_found' };
  }

  if (sku.companyId) {
    return sku.companyId === companyId ? { status: 'ok', sku } : { status: 'forbidden' };
  }

  const linkedToCompany = await prisma.coilItem.findFirst({
    where: {
      skuId,
      coil: {
        machine: {
          companyId,
        },
      },
    },
    select: { id: true },
  });

  if (!linkedToCompany) {
    return { status: 'forbidden' };
  }

  return { status: 'ok', sku };
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

function buildSkuCompanyWhere(companyId: string): Prisma.SKUWhereInput {
  return {
    OR: [
      { companyId },
      {
        companyId: null,
        coilItems: {
          some: {
            coil: {
              machine: {
                companyId,
              },
            },
          },
        },
      },
    ],
  };
}

export const skuRouter = router;
