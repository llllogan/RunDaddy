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

  // Check if SKU belongs to user's company
  const sku = await prisma.sKU.findFirst({
    where: {
      id: skuId,
    },
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

  // Calculate date ranges for week, month, quarter
  const weekStart = getTimezoneDayRange({ timeZone: timeZone!, dayOffset: -7, reference: now });
  const monthStart = getTimezoneDayRange({ timeZone: timeZone!, dayOffset: -30, reference: now });
  const quarterStart = getTimezoneDayRange({ timeZone: timeZone!, dayOffset: -90, reference: now });
  const today = getTimezoneDayRange({ timeZone: timeZone!, dayOffset: 0, reference: now });

  const [weekData, monthData, quarterData, mostRecentPick] = await Promise.all([
    getSkuStats(skuId, weekStart.start, today.end, req.auth!.companyId, timeZone),
    getSkuStats(skuId, monthStart.start, today.end, req.auth!.companyId, timeZone),
    getSkuStats(skuId, quarterStart.start, today.end, req.auth!.companyId, timeZone),
    getMostRecentPick(skuId, req.auth!.companyId),
  ]);

  // Calculate percentage changes
  const weekChange = await calculatePercentageChange(skuId, weekStart.start, today.end, req.auth!.companyId, 'week');
  const monthChange = await calculatePercentageChange(skuId, monthStart.start, today.end, req.auth!.companyId, 'month');
  const quarterChange = await calculatePercentageChange(skuId, quarterStart.start, today.end, req.auth!.companyId, 'quarter');

  return res.json({
    generatedAt: new Date().toISOString(),
    timeZone,
    mostRecentPick,
    percentageChanges: {
      week: weekChange,
      month: monthChange,
      quarter: quarterChange,
    },
    periods: {
      week: weekData,
      month: monthData,
      quarter: quarterData,
    },
  });
});

async function getSkuStats(skuId: string, startDate: Date, endDate: Date, companyId: string, timeZone: string) {
  const rows = await prisma.$queryRaw<Array<{
    date: string;
    locationId: string;
    locationName: string;
    totalPicked: bigint;
  }>>(
    Prisma.sql`
      SELECT 
        formatted_date AS date,
        loc.id AS locationId,
        loc.name AS locationName,
        SUM(pe.count) AS totalPicked
      FROM (
        SELECT 
          DATE_FORMAT(CONVERT_TZ(pe.pickedAt, 'UTC', ${timeZone}), '%Y-%m-%d') AS formatted_date,
          pe.count,
          mach.locationId
        FROM PickEntry pe
        JOIN CoilItem ci ON ci.id = pe.coilItemId
        JOIN Coil coil ON coil.id = ci.coilId
        JOIN Machine mach ON mach.id = coil.machineId
        JOIN Run r ON r.id = pe.runId
        WHERE ci.skuId = ${skuId}
          AND pe.status = 'PICKED'
          AND pe.pickedAt IS NOT NULL
          AND pe.pickedAt >= ${startDate}
          AND pe.pickedAt < ${endDate}
          AND r.companyId = ${companyId}
          AND mach.locationId IS NOT NULL
      ) AS pe_with_date
      JOIN Location loc ON loc.id = pe_with_date.locationId
      GROUP BY formatted_date, loc.id, loc.name
      ORDER BY formatted_date ASC, locationName ASC
    `
  );

  // Group by date and calculate totals
  const dailyStats = new Map<string, { total: number; locations: Array<{ name: string; count: number }> }>();
  
  for (const row of rows) {
    const date = row.date;
    const count = Number(row.totalPicked);
    
    if (!dailyStats.has(date)) {
      dailyStats.set(date, { total: 0, locations: [] });
    }
    
    const stat = dailyStats.get(date)!;
    stat.total += count;
    stat.locations.push({
      name: row.locationName || 'Unknown',
      count,
    });
  }

  return Array.from(dailyStats.entries()).map(([date, data]) => ({
    date,
    total: data.total,
    locations: data.locations,
  }));
}

async function getMostRecentPick(skuId: string, companyId: string) {
  const result = await prisma.$queryRaw<Array<{
    pickedAt: Date;
    locationName: string;
    runId: string;
  }>>(
    Prisma.sql`
      SELECT 
        pe.pickedAt,
        loc.name AS locationName,
        r.id AS runId
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Coil coil ON coil.id = ci.coilId
      JOIN Machine mach ON mach.id = coil.machineId
      LEFT JOIN Location loc ON loc.id = mach.locationId
      JOIN Run r ON r.id = pe.runId
      WHERE ci.skuId = ${skuId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt IS NOT NULL
        AND r.companyId = ${companyId}
      ORDER BY pe.pickedAt DESC
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
    pickedAt: row.pickedAt.toISOString(),
    locationName: row.locationName || 'Unknown',
    runId: row.runId,
  };
}

async function calculatePercentageChange(
  skuId: string, 
  currentPeriodStart: Date, 
  currentPeriodEnd: Date, 
  companyId: string,
  periodType: 'week' | 'month' | 'quarter'
): Promise<{ value: number; trend: 'up' | 'down' | 'neutral' } | null> {
  const periodDays = periodType === 'week' ? 7 : periodType === 'month' ? 30 : 90;
  const previousPeriodStart = new Date(currentPeriodStart.getTime() - (periodDays * 24 * 60 * 60 * 1000));
  const previousPeriodEnd = currentPeriodStart;

  // Get current period data
  const currentResult = await prisma.$queryRaw<Array<{ totalPicked: bigint }>>(
    Prisma.sql`
      SELECT SUM(pe.count) AS totalPicked
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Run r ON r.id = pe.runId
      WHERE ci.skuId = ${skuId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt >= ${currentPeriodStart}
        AND pe.pickedAt < ${currentPeriodEnd}
        AND r.companyId = ${companyId}
    `
  );

  // Get previous period data
  const previousResult = await prisma.$queryRaw<Array<{ totalPicked: bigint }>>(
    Prisma.sql`
      SELECT SUM(pe.count) AS totalPicked
      FROM PickEntry pe
      JOIN CoilItem ci ON ci.id = pe.coilItemId
      JOIN Run r ON r.id = pe.runId
      WHERE ci.skuId = ${skuId}
        AND pe.status = 'PICKED'
        AND pe.pickedAt >= ${previousPeriodStart}
        AND pe.pickedAt < ${previousPeriodEnd}
        AND r.companyId = ${companyId}
    `
  );

  const currentTotal = Number(currentResult[0]?.totalPicked || 0);
  const previousTotal = Number(previousResult[0]?.totalPicked || 0);

  // If no data in either period, return null
  if (currentTotal === 0 && previousTotal === 0) {
    return null;
  }

  // If no previous data but current data exists, show as positive trend
  if (previousTotal === 0 && currentTotal > 0) {
    return { value: 100, trend: 'up' };
  }

  // If previous data exists but no current data, show as negative trend
  if (previousTotal > 0 && currentTotal === 0) {
    return { value: -100, trend: 'down' };
  }

  // Calculate percentage change
  const percentageChange = ((currentTotal - previousTotal) / previousTotal) * 100;
  
  let trend: 'up' | 'down' | 'neutral';
  if (percentageChange > 0.5) {
    trend = 'up';
  } else if (percentageChange < -0.5) {
    trend = 'down';
  } else {
    trend = 'neutral';
  }

  return {
    value: Math.round(percentageChange * 10) / 10, // Round to 1 decimal place
    trend
  };
}

export const skuRouter = router;