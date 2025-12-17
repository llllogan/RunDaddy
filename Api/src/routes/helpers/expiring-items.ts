import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma.js';
import { formatDateInTimezone, getTimezoneDayRange } from '../../lib/timezone.js';
import { ensureRun } from './runs.js';
import { resolveCompanyTimezone } from './timezone.js';

type ExpiringItemsSectionItem = {
  quantity: number;
  coilItemId: string;
  sku: {
    id: string;
    code: string;
    name: string;
    type: string;
  };
  machine: {
    id: string;
    code: string;
    description: string | null;
  };
  coil: {
    id: string;
    code: string;
  };
};

export type ExpiringItemsSection = {
  expiryDate: string; // YYYY-MM-DD, in company timezone
  dayOffset: 0;
  items: ExpiringItemsSectionItem[];
};

export type ExpiringItemsRunResponse = {
  warningCount: number;
  sections: ExpiringItemsSection[];
};

type UpcomingExpiringItemsSectionItem = ExpiringItemsSectionItem & {
  plannedQuantity: number;
  expiringQuantity: number;
  stockingRun: {
    id: string;
    runDate: string; // YYYY-MM-DD in company timezone
  } | null;
};

export type UpcomingExpiringItemsSection = {
  expiryDate: string; // YYYY-MM-DD, in company timezone
  items: UpcomingExpiringItemsSectionItem[];
};

export type UpcomingExpiringItemsResponse = {
  warningCount: number;
  sections: UpcomingExpiringItemsSection[];
};

export type AddNeededForExpiryResult = {
  addedQuantity: number;
  expiringQuantity: number;
  coilCode: string;
  runDate: string; // YYYY-MM-DD in company timezone
};

type PickEntryCountSource = {
  count: number;
  override: number | null;
  current: number | null;
  par: number | null;
  need: number | null;
  forecast: number | null;
  total: number | null;
  coilItemId: string;
  coilItem: {
    sku: {
      countNeededPointer: string | null;
    } | null;
  };
};

const hasOverrideValue = (value: number | null | undefined): value is number =>
  value !== null && value !== undefined;

const resolvePointerCount = (entry: PickEntryCountSource, fallbackCount?: number): number => {
  const pointer = (entry.coilItem.sku?.countNeededPointer || 'total').toLowerCase();
  const safeFallback = fallbackCount ?? entry.count;

  switch (pointer) {
    case 'current':
      return entry.current ?? safeFallback;
    case 'par':
      return entry.par ?? safeFallback;
    case 'need':
      return entry.need ?? safeFallback;
    case 'forecast':
      return entry.forecast ?? safeFallback;
    case 'total':
    default:
      return entry.total ?? safeFallback;
  }
};

const resolvePickEntryCount = (entry: PickEntryCountSource): number => {
  if (hasOverrideValue(entry.override)) {
    return entry.override;
  }

  return resolvePointerCount(entry);
};

type ExpiringQuantityRow = {
  coil_item_id: string;
  sku_id: string;
  sku_code: string;
  sku_name: string;
  sku_type: string;
  coil_id: string;
  coil_code: string;
  machine_id: string;
  machine_code: string;
  machine_description: string | null;
  expiry_date: string;
  expiring_quantity: bigint | number | string;
};

const parseQueryNumber = (value: bigint | number | string): number => {
  if (typeof value === 'bigint') {
    return Number(value);
  }
  if (typeof value === 'number') {
    return value;
  }
  return Number.parseInt(value, 10);
};

const buildResolvedCountSql = () => Prisma.sql`
  CASE
    WHEN pe.override IS NOT NULL THEN pe.override
    WHEN LOWER(COALESCE(s.countNeededPointer, 'total')) = 'current' THEN COALESCE(pe.current, pe.count)
    WHEN LOWER(COALESCE(s.countNeededPointer, 'total')) = 'par' THEN COALESCE(pe.par, pe.count)
    WHEN LOWER(COALESCE(s.countNeededPointer, 'total')) = 'need' THEN COALESCE(pe.need, pe.count)
    WHEN LOWER(COALESCE(s.countNeededPointer, 'total')) = 'forecast' THEN COALESCE(pe.forecast, pe.count)
    ELSE COALESCE(pe.total, pe.count)
  END
`;

const isValidFiniteNumber = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value);

export async function buildExpiringItemsForRun(
  companyId: string,
  runId: string,
): Promise<ExpiringItemsRunResponse | null> {
  const run = await ensureRun(companyId, runId);
  if (!run) {
    return null;
  }
  if (!run.scheduledFor) {
    return { warningCount: 0, sections: [] };
  }

  const timeZone = await resolveCompanyTimezone(companyId);

  const runDayRange = getTimezoneDayRange({ timeZone, reference: run.scheduledFor!, dayOffset: 0 });

  const coilItemIds = Array.from(
    new Set(run.pickEntries.map((entry) => entry.coilItemId).filter((value): value is string => Boolean(value))),
  );

  if (!coilItemIds.length) {
    return { warningCount: 0, sections: [] };
  }

  const plannedRestocks = new Map<string, number>();
  run.pickEntries.forEach((entry) => {
    const plannedCount = resolvePickEntryCount(entry as unknown as PickEntryCountSource);
    if (plannedCount <= 0) {
      return;
    }
    plannedRestocks.set(entry.coilItemId, (plannedRestocks.get(entry.coilItemId) ?? 0) + plannedCount);
  });

  const currentByCoilItemId = new Map<string, number>();
  run.pickEntries.forEach((entry) => {
    if (typeof entry.current !== 'number' || !Number.isFinite(entry.current)) {
      return;
    }
    currentByCoilItemId.set(entry.coilItemId, Math.max(0, entry.current));
  });

  const resolvedCountSql = buildResolvedCountSql();
  const targetLabels = [runDayRange.label];

  const expiringRows = await prisma.$queryRaw<ExpiringQuantityRow[]>(
    Prisma.sql`
      SELECT
        pe.coilItemId AS coil_item_id,
        s.id AS sku_id,
        s.code AS sku_code,
        s.name AS sku_name,
        s.type AS sku_type,
        c.id AS coil_id,
        c.code AS coil_code,
        m.id AS machine_id,
        m.code AS machine_code,
        m.description AS machine_description,
        DATE_FORMAT(
          DATE_ADD(CONVERT_TZ(r.scheduledFor, 'UTC', ${timeZone}), INTERVAL (s.expiryDays - 1) DAY),
          '%Y-%m-%d'
        ) AS expiry_date,
        SUM(${resolvedCountSql}) AS expiring_quantity
      FROM PickEntry pe
        INNER JOIN Run r ON r.id = pe.runId
        INNER JOIN CoilItem ci ON ci.id = pe.coilItemId
        INNER JOIN Coil c ON c.id = ci.coilId
        INNER JOIN Machine m ON m.id = c.machineId
        INNER JOIN SKU s ON s.id = ci.skuId
      WHERE r.companyId = ${companyId}
        AND pe.coilItemId IN (${Prisma.join(coilItemIds)})
        AND r.scheduledFor IS NOT NULL
        AND s.expiryDays > 0
      GROUP BY
        coil_item_id,
        sku_id,
        sku_code,
        sku_name,
        coil_id,
        coil_code,
        machine_id,
        machine_code,
        machine_description,
        expiry_date
      HAVING expiry_date IN (${Prisma.join(targetLabels)})
        AND expiring_quantity > 0
    `,
  );

  if (!expiringRows.length) {
    return { warningCount: 0, sections: [] };
  }

  const expiringByCoilItem = new Map<string, number>();
  const detailsByCoilItemByDate = new Map<string, ExpiringItemsSectionItem>();

  expiringRows.forEach((row) => {
    const expiringQty = parseQueryNumber(row.expiring_quantity);
    if (!Number.isFinite(expiringQty) || expiringQty <= 0) {
      return;
    }

    expiringByCoilItem.set(row.coil_item_id, (expiringByCoilItem.get(row.coil_item_id) ?? 0) + expiringQty);

    const detailKey = `${row.coil_item_id}:${row.expiry_date}`;
    if (!detailsByCoilItemByDate.has(detailKey)) {
      detailsByCoilItemByDate.set(detailKey, {
        quantity: 0,
        coilItemId: row.coil_item_id,
      sku: {
        id: row.sku_id,
        code: row.sku_code,
        name: row.sku_name,
        type: row.sku_type,
      },
        machine: {
          id: row.machine_id,
          code: row.machine_code,
          description: row.machine_description,
        },
        coil: {
          id: row.coil_id,
          code: row.coil_code,
        },
      });
    }
  });

  const warningItemsByDate = new Map<string, { dayOffset: 0; items: ExpiringItemsSectionItem[] }>();

  const addWarningItem = (coilItemId: string, expiryDate: string, quantity: number) => {
    if (quantity <= 0) {
      return;
    }

    const detailKey = `${coilItemId}:${expiryDate}`;
    const baseDetails = detailsByCoilItemByDate.get(detailKey);
    if (!baseDetails) {
      return;
    }

    const warningItem: ExpiringItemsSectionItem = {
      ...baseDetails,
      quantity,
    };

    if (!warningItemsByDate.has(expiryDate)) {
      warningItemsByDate.set(expiryDate, { dayOffset: 0, items: [] });
    }
    warningItemsByDate.get(expiryDate)!.items.push(warningItem);
  };

  for (const [coilItemId, expiringQty] of expiringByCoilItem.entries()) {
    const currentCount = currentByCoilItemId.get(coilItemId);
    const expToday = currentCount === undefined ? (expiringQty ?? 0) : Math.min(expiringQty ?? 0, currentCount);
    const restToday = plannedRestocks.get(coilItemId) ?? 0;

    const missingToday = Math.max(0, expToday - restToday);

    addWarningItem(coilItemId, runDayRange.label, missingToday);
  }

  const sections: ExpiringItemsSection[] = Array.from(warningItemsByDate.entries())
    .map(([expiryDate, group]) => ({
      expiryDate,
      dayOffset: group.dayOffset,
      items: group.items.sort((a, b) => {
        const skuCompare = a.sku.name.localeCompare(b.sku.name);
        if (skuCompare !== 0) {
          return skuCompare;
        }
        const machineCompare = a.machine.code.localeCompare(b.machine.code);
        if (machineCompare !== 0) {
          return machineCompare;
        }
        return a.coil.code.localeCompare(b.coil.code);
      }),
    }))
    .sort((a, b) => a.expiryDate.localeCompare(b.expiryDate));

  const warningCount = sections.reduce((sum, section) => sum + section.items.length, 0);

  return { warningCount, sections };
}

export async function buildUpcomingExpiringItems({
  companyId,
  daysAhead = 14,
}: {
  companyId: string;
  daysAhead?: number;
}): Promise<UpcomingExpiringItemsResponse> {
  const resolvedDaysAhead = Number.isFinite(daysAhead) ? Math.max(0, Math.min(28, Math.floor(daysAhead))) : 14;

  const timeZone = await resolveCompanyTimezone(companyId);
  const windowStart = getTimezoneDayRange({ timeZone, reference: new Date(), dayOffset: 0 });
  const windowEnd = getTimezoneDayRange({ timeZone, reference: new Date(), dayOffset: resolvedDaysAhead });
  const windowEndExclusive = getTimezoneDayRange({ timeZone, reference: new Date(), dayOffset: resolvedDaysAhead + 1 });
  const lookbackStart = new Date(windowStart.start);
  lookbackStart.setUTCDate(lookbackStart.getUTCDate() - 120);

  const resolvedCountSql = buildResolvedCountSql();

  const expiringRows = await prisma.$queryRaw<ExpiringQuantityRow[]>(
    Prisma.sql`
      SELECT
        pe.coilItemId AS coil_item_id,
        s.id AS sku_id,
        s.code AS sku_code,
        s.name AS sku_name,
        c.id AS coil_id,
        c.code AS coil_code,
        m.id AS machine_id,
        m.code AS machine_code,
        m.description AS machine_description,
        DATE_FORMAT(
          DATE_ADD(CONVERT_TZ(r.scheduledFor, 'UTC', ${timeZone}), INTERVAL (s.expiryDays - 1) DAY),
          '%Y-%m-%d'
        ) AS expiry_date,
        SUM(${resolvedCountSql}) AS expiring_quantity
      FROM PickEntry pe
        INNER JOIN Run r ON r.id = pe.runId
        INNER JOIN CoilItem ci ON ci.id = pe.coilItemId
        INNER JOIN Coil c ON c.id = ci.coilId
        INNER JOIN Machine m ON m.id = c.machineId
        INNER JOIN SKU s ON s.id = ci.skuId
      WHERE r.companyId = ${companyId}
        AND r.scheduledFor IS NOT NULL
        AND s.expiryDays > 0
      GROUP BY
        coil_item_id,
        sku_id,
        sku_code,
        sku_name,
        coil_id,
        coil_code,
        machine_id,
        machine_code,
        machine_description,
        expiry_date
      HAVING expiry_date BETWEEN ${windowStart.label} AND ${windowEnd.label}
        AND expiring_quantity > 0
    `,
  );

  if (!expiringRows.length) {
    return { warningCount: 0, sections: [] };
  }

  const coilItemIds = Array.from(new Set(expiringRows.map((row) => row.coil_item_id).filter(Boolean)));

  const relevantPickEntries = await prisma.pickEntry.findMany({
    where: {
      coilItemId: { in: coilItemIds },
      run: {
        companyId,
        scheduledFor: {
          gte: lookbackStart,
          lt: windowEndExclusive.start,
        },
      },
    },
    select: {
      coilItemId: true,
      count: true,
      override: true,
      current: true,
      par: true,
      need: true,
      forecast: true,
      total: true,
      coilItem: {
        select: {
          sku: {
            select: {
              countNeededPointer: true,
            },
          },
        },
      },
      run: {
        select: {
          id: true,
          scheduledFor: true,
        },
      },
    },
  });

  const upcomingByCoilItemId = new Map<
    string,
    Array<{
      runId: string;
      runDate: string;
      plannedQuantity: number;
      current: number | null;
    }>
  >();

  for (const entry of relevantPickEntries) {
    if (!entry.run?.scheduledFor) {
      continue;
    }

    const runDate = formatDateInTimezone(entry.run.scheduledFor, timeZone);
    const plannedQuantity = resolvePickEntryCount(entry as unknown as PickEntryCountSource);
    const current = isValidFiniteNumber(entry.current) ? Math.max(0, entry.current) : null;

    if (!upcomingByCoilItemId.has(entry.coilItemId)) {
      upcomingByCoilItemId.set(entry.coilItemId, []);
    }
    upcomingByCoilItemId.get(entry.coilItemId)!.push({
      runId: entry.run.id,
      runDate,
      plannedQuantity: Math.max(0, plannedQuantity),
      current,
    });
  }

  for (const entries of upcomingByCoilItemId.values()) {
    entries.sort((a, b) => a.runDate.localeCompare(b.runDate));
  }

  const detailsByCoilItemByDate = new Map<string, ExpiringItemsSectionItem>();
  expiringRows.forEach((row) => {
    const detailKey = `${row.coil_item_id}:${row.expiry_date}`;
    if (!detailsByCoilItemByDate.has(detailKey)) {
      detailsByCoilItemByDate.set(detailKey, {
        quantity: 0,
        coilItemId: row.coil_item_id,
        sku: {
          id: row.sku_id,
          code: row.sku_code,
          name: row.sku_name,
          type: row.sku_type,
        },
        machine: {
          id: row.machine_id,
          code: row.machine_code,
          description: row.machine_description,
        },
        coil: {
          id: row.coil_id,
          code: row.coil_code,
        },
      });
    }
  });

  const sectionsByDate = new Map<string, UpcomingExpiringItemsSectionItem[]>();

  const findCurrentCapForExpiry = (
    entries: Array<{
      runId: string;
      runDate: string;
      plannedQuantity: number;
      current: number | null;
    }>,
    expiryDate: string,
  ): number | null => {
    if (!entries.length) {
      return null;
    }

    for (let i = entries.length - 1; i >= 0; i -= 1) {
      const entry = entries[i];
      if (!entry) {
        continue;
      }
      if (entry.runDate > expiryDate) {
        continue;
      }
      if (entry.current === null) {
        continue;
      }
      return entry.current;
    }

    return null;
  };

  for (const row of expiringRows) {
    const expiringQuantity = parseQueryNumber(row.expiring_quantity);
    if (!Number.isFinite(expiringQuantity) || expiringQuantity <= 0) {
      continue;
    }

    const expiryDate = row.expiry_date;
    const detailKey = `${row.coil_item_id}:${expiryDate}`;
    const baseDetails = detailsByCoilItemByDate.get(detailKey);
    if (!baseDetails) {
      continue;
    }

    const upcomingEntries = upcomingByCoilItemId.get(row.coil_item_id) ?? [];

    const plannedQuantity = upcomingEntries
      .filter((entry) => entry.runDate === expiryDate)
      .reduce((sum, entry) => sum + entry.plannedQuantity, 0);
    const stockingRunId = upcomingEntries.find((entry) => entry.runDate === expiryDate)?.runId ?? null;

    const currentCap = findCurrentCapForExpiry(upcomingEntries, expiryDate);

    const cappedExpiringQuantity = currentCap === null ? expiringQuantity : Math.min(expiringQuantity, currentCap);

    const missingQuantity = Math.max(0, cappedExpiringQuantity - plannedQuantity);

    if (missingQuantity <= 0) {
      continue;
    }

    const item: UpcomingExpiringItemsSectionItem = {
      ...baseDetails,
      quantity: missingQuantity,
      plannedQuantity,
      expiringQuantity: cappedExpiringQuantity,
      stockingRun: stockingRunId
        ? {
            id: stockingRunId,
            runDate: expiryDate,
          }
        : null,
    };

    if (!sectionsByDate.has(expiryDate)) {
      sectionsByDate.set(expiryDate, []);
    }
    sectionsByDate.get(expiryDate)!.push(item);
  }

  const sections: UpcomingExpiringItemsSection[] = Array.from(sectionsByDate.entries())
    .map(([expiryDate, items]) => ({
      expiryDate,
      items: items.sort((a, b) => {
        const skuCompare = a.sku.name.localeCompare(b.sku.name);
        if (skuCompare !== 0) {
          return skuCompare;
        }
        const machineCompare = a.machine.code.localeCompare(b.machine.code);
        if (machineCompare !== 0) {
          return machineCompare;
        }
        return a.coil.code.localeCompare(b.coil.code);
      }),
    }))
    .sort((a, b) => a.expiryDate.localeCompare(b.expiryDate));

  const warningCount = sections.reduce((sum, section) => sum + section.items.length, 0);

  return { warningCount, sections };
}

type ExpiringSumRow = {
  expiring_quantity: bigint | number | string | null;
};

export async function addNeededForRunDayExpiry({
  companyId,
  runId,
  coilItemId,
  userId,
}: {
  companyId: string;
  runId: string;
  coilItemId: string;
  userId: string | null;
}): Promise<AddNeededForExpiryResult | null> {
  const run = await prisma.run.findUnique({
    where: { id: runId },
    select: {
      id: true,
      companyId: true,
      scheduledFor: true,
    },
  });
  if (!run || run.companyId !== companyId || !run.scheduledFor) {
    return null;
  }

  const timeZone = await resolveCompanyTimezone(companyId);
  const runDayLabel = getTimezoneDayRange({ timeZone, reference: run.scheduledFor, dayOffset: 0 }).label;

  const pickEntry = await prisma.pickEntry.findUnique({
    where: {
      runId_coilItemId: {
        runId,
        coilItemId,
      },
    },
    include: {
      coilItem: {
        include: {
          sku: true,
          coil: true,
        },
      },
    },
  });

  if (!pickEntry || !pickEntry.coilItem?.sku || !pickEntry.coilItem?.coil) {
    return null;
  }

  const plannedCount = resolvePickEntryCount(pickEntry as unknown as PickEntryCountSource);

  const resolvedCountSql = buildResolvedCountSql();
  const expiringSum = await prisma.$queryRaw<ExpiringSumRow[]>(
    Prisma.sql`
      SELECT
        SUM(${resolvedCountSql}) AS expiring_quantity
      FROM PickEntry pe
        INNER JOIN Run r ON r.id = pe.runId
        INNER JOIN CoilItem ci ON ci.id = pe.coilItemId
        INNER JOIN SKU s ON s.id = ci.skuId
      WHERE r.companyId = ${companyId}
        AND pe.coilItemId = ${coilItemId}
        AND r.scheduledFor IS NOT NULL
        AND s.expiryDays > 0
        AND DATE_FORMAT(
          DATE_ADD(CONVERT_TZ(r.scheduledFor, 'UTC', ${timeZone}), INTERVAL (s.expiryDays - 1) DAY),
          '%Y-%m-%d'
        ) = ${runDayLabel}
    `,
  );

  const expiringQuantity = expiringSum.length
    ? parseQueryNumber(expiringSum[0]?.expiring_quantity ?? 0)
    : 0;
  const currentCount = typeof pickEntry.current === 'number' && Number.isFinite(pickEntry.current)
    ? Math.max(0, pickEntry.current)
    : null;
  const remainingExpiringQuantity = currentCount === null ? expiringQuantity : Math.min(expiringQuantity, currentCount);
  const addedQuantity = Math.max(0, remainingExpiringQuantity - plannedCount);

  if (addedQuantity <= 0) {
    return {
      addedQuantity: 0,
      expiringQuantity: remainingExpiringQuantity,
      coilCode: pickEntry.coilItem.coil.code,
      runDate: runDayLabel,
    };
  }

  await prisma.pickEntry.update({
    where: {
      runId_coilItemId: {
        runId,
        coilItemId,
      },
    },
    data: {
      override: remainingExpiringQuantity,
      count: remainingExpiringQuantity,
    },
  });

  await prisma.note.create({
    data: {
      companyId,
      runId,
      machineId: pickEntry.coilItem.coil.machineId,
      body: `Coil ${pickEntry.coilItem.coil.code} has ${addedQuantity} items expiring`,
      createdBy: userId,
    },
  });

  return {
    addedQuantity,
    expiringQuantity: remainingExpiringQuantity,
    coilCode: pickEntry.coilItem.coil.code,
    runDate: runDayLabel,
  };
}
