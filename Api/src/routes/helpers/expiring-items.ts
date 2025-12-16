import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma.js';
import { getTimezoneDayRange } from '../../lib/timezone.js';
import { ensureRun } from './runs.js';
import { resolveCompanyTimezone } from './timezone.js';

type ExpiringItemsSectionItem = {
  quantity: number;
  sku: {
    id: string;
    code: string;
    name: string;
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
  dayOffset: -2 | -1 | 0;
  items: ExpiringItemsSectionItem[];
};

export type ExpiringItemsRunResponse = {
  warningCount: number;
  sections: ExpiringItemsSection[];
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
  coil_id: string;
  coil_code: string;
  machine_id: string;
  machine_code: string;
  machine_description: string | null;
  expiry_date: string;
  expiring_quantity: bigint | number | string;
};

type RestockedQuantityRow = {
  coil_item_id: string;
  restocked_quantity: bigint | number | string;
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

  const targetOffsets: Array<-2 | -1 | 0> = [-2, -1, 0];
  const dayRanges = targetOffsets.map((dayOffset) => ({
    dayOffset,
    range: getTimezoneDayRange({ timeZone, reference: run.scheduledFor!, dayOffset }),
  }));

  const labelToOffset = new Map<string, -2 | -1 | 0>();
  dayRanges.forEach(({ dayOffset, range }) => {
    labelToOffset.set(range.label, dayOffset);
  });

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

  const resolvedCountSql = buildResolvedCountSql();
  const targetLabels = dayRanges.map(({ range }) => range.label);

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

  const restocksByOffset = new Map<-2 | -1, Map<string, number>>();
  for (const { dayOffset, range } of dayRanges) {
    if (dayOffset === 0) {
      continue;
    }

    const restockedRows = await prisma.$queryRaw<RestockedQuantityRow[]>(
      Prisma.sql`
        SELECT
          pe.coilItemId AS coil_item_id,
          SUM(${resolvedCountSql}) AS restocked_quantity
        FROM PickEntry pe
          INNER JOIN Run r ON r.id = pe.runId
          INNER JOIN CoilItem ci ON ci.id = pe.coilItemId
          INNER JOIN SKU s ON s.id = ci.skuId
        WHERE r.companyId = ${companyId}
          AND pe.coilItemId IN (${Prisma.join(coilItemIds)})
          AND r.scheduledFor >= ${range.start}
          AND r.scheduledFor < ${range.end}
        GROUP BY coil_item_id
        HAVING restocked_quantity > 0
      `,
    );

    const byCoilItem = new Map<string, number>();
    restockedRows.forEach((row) => {
      byCoilItem.set(row.coil_item_id, parseQueryNumber(row.restocked_quantity));
    });
    restocksByOffset.set(dayOffset, byCoilItem);
  }

  const expiringByCoilItemByOffset = new Map<string, Map<-2 | -1 | 0, number>>();
  const detailsByCoilItemByDate = new Map<string, ExpiringItemsSectionItem>();

  expiringRows.forEach((row) => {
    const offset = labelToOffset.get(row.expiry_date);
    if (offset === undefined) {
      return;
    }

    const expiringQty = parseQueryNumber(row.expiring_quantity);
    if (!Number.isFinite(expiringQty) || expiringQty <= 0) {
      return;
    }

    if (!expiringByCoilItemByOffset.has(row.coil_item_id)) {
      expiringByCoilItemByOffset.set(row.coil_item_id, new Map());
    }
    const expiringByOffset = expiringByCoilItemByOffset.get(row.coil_item_id)!;
    expiringByOffset.set(offset, (expiringByOffset.get(offset) ?? 0) + expiringQty);

    const detailKey = `${row.coil_item_id}:${row.expiry_date}`;
    if (!detailsByCoilItemByDate.has(detailKey)) {
      detailsByCoilItemByDate.set(detailKey, {
        quantity: 0,
        sku: {
          id: row.sku_id,
          code: row.sku_code,
          name: row.sku_name,
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

  const warningItemsByDate = new Map<string, { dayOffset: -2 | -1 | 0; items: ExpiringItemsSectionItem[] }>();

  const resolveExpiryDate = (offset: -2 | -1 | 0) =>
    dayRanges.find((entry) => entry.dayOffset === offset)!.range.label;

  const addWarningItem = (coilItemId: string, expiryDate: string, dayOffset: -2 | -1 | 0, quantity: number) => {
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
      warningItemsByDate.set(expiryDate, { dayOffset, items: [] });
    }
    warningItemsByDate.get(expiryDate)!.items.push(warningItem);
  };

  for (const [coilItemId, expiringByOffset] of expiringByCoilItemByOffset.entries()) {
    const expTwoDaysAgo = expiringByOffset.get(-2) ?? 0;
    const expYesterday = expiringByOffset.get(-1) ?? 0;
    const expToday = expiringByOffset.get(0) ?? 0;

    const restTwoDaysAgo = restocksByOffset.get(-2)?.get(coilItemId) ?? 0;
    const restYesterday = restocksByOffset.get(-1)?.get(coilItemId) ?? 0;
    const restToday = plannedRestocks.get(coilItemId) ?? 0;

    const missingToday = Math.max(0, expToday - restToday);
    const missingYesterday = Math.max(0, expYesterday - restYesterday);
    const missingTwoDaysAgo = Math.max(0, expTwoDaysAgo - restTwoDaysAgo);

    addWarningItem(coilItemId, resolveExpiryDate(0), 0, missingToday);
    addWarningItem(coilItemId, resolveExpiryDate(-1), -1, missingYesterday);
    addWarningItem(coilItemId, resolveExpiryDate(-2), -2, missingTwoDaysAgo);
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
