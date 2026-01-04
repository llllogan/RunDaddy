import { prisma } from '../../lib/prisma.js';
import { getTimezoneDayRange } from '../../lib/timezone.js';
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
    locationId: string | null;
    location: {
      id: string;
      name: string | null;
      address: string | null;
    } | null;
  };
  coil: {
    id: string;
    code: string;
  };
  isIgnored: boolean;
  ignoredAt: string | null;
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
  isIgnored: boolean;
  ignoredAt: string | null;
};

type PickEntryExpiryOverrideRow = {
  expiryDate: string;
  quantity: number;
};

type PickEntryExpiryLot = {
  expiryDate: string;
  quantity: number;
};

type ExpiryIgnoreRow = {
  coilItemId: string;
  expiryDate: string;
  quantity: number;
  ignoredAt: Date;
};

export type UpcomingExpiringItemsSection = {
  expiryDate: string; // YYYY-MM-DD, in company timezone
  items: UpcomingExpiringItemsSectionItem[];
  runs: Array<{
    id: string;
    runDate: string; // YYYY-MM-DD, in company timezone
    locationIds: string[];
    machineIds: string[];
    locations: Array<{
      id: string;
      name: string | null;
      address: string | null;
    }>;
  }>;
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

type PlannedRunEntry = {
  runAtMs: number;
  plannedQuantity: number;
};

type PlannedIndex = {
  runAtMs: number[];
  prefixSum: number[];
  total: number;
};

const buildPlannedIndex = (entries: PlannedRunEntry[]): PlannedIndex => {
  const sorted = entries
    .filter((entry) => entry.plannedQuantity > 0)
    .sort((a, b) => a.runAtMs - b.runAtMs);

  const runAtMs: number[] = [];
  const prefixSum: number[] = [];
  let total = 0;

  for (const entry of sorted) {
    runAtMs.push(entry.runAtMs);
    total += entry.plannedQuantity;
    prefixSum.push(total);
  }

  return { runAtMs, prefixSum, total };
};

const findFirstGreater = (values: number[], target: number): number => {
  let low = 0;
  let high = values.length;

  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    if ((values[mid] ?? 0) <= target) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }

  return low;
};

const sumPlannedAfter = (index: PlannedIndex, afterMs: number): number => {
  const startIndex = findFirstGreater(index.runAtMs, afterMs);
  if (startIndex >= index.runAtMs.length) {
    return 0;
  }

  const sumBefore = startIndex > 0 ? (index.prefixSum[startIndex - 1] ?? 0) : 0;
  return Math.max(0, index.total - sumBefore);
};

const buildExpiryLots = ({
  baseExpiryDate,
  plannedCount,
  overrides,
}: {
  baseExpiryDate: string | null | undefined;
  plannedCount: number;
  overrides: PickEntryExpiryOverrideRow[] | null | undefined;
}): PickEntryExpiryLot[] => {
  const normalizedBase = baseExpiryDate?.trim() ?? '';
  const normalizedOverrides = overrides ?? [];

  const lotsByDate = new Map<string, number>();
  let overrideTotal = 0;

  for (const row of normalizedOverrides) {
    const date = row.expiryDate?.trim() ?? '';
    if (!date) {
      continue;
    }
    const quantity = Math.max(0, Math.floor(row.quantity ?? 0));
    if (quantity <= 0) {
      continue;
    }
    lotsByDate.set(date, (lotsByDate.get(date) ?? 0) + quantity);
    overrideTotal += quantity;
  }

  const remainder = Math.max(0, plannedCount - overrideTotal);
  if (remainder > 0 && normalizedBase) {
    lotsByDate.set(normalizedBase, (lotsByDate.get(normalizedBase) ?? 0) + remainder);
  }

  return Array.from(lotsByDate.entries())
    .map(([expiryDate, quantity]) => ({ expiryDate, quantity }))
    .filter((lot) => lot.expiryDate.trim().length > 0 && lot.quantity > 0)
    .sort((a, b) => a.expiryDate.localeCompare(b.expiryDate));
};

const applyRestockConsumption = (lots: PickEntryExpiryLot[], restockedAfter: number): PickEntryExpiryLot[] => {
  if (!lots.length) {
    return [];
  }

  let remainingSold = Math.max(0, Math.floor(restockedAfter));
  const nextLots: PickEntryExpiryLot[] = [];

  for (const lot of lots) {
    if (lot.quantity <= 0) {
      continue;
    }

    const soldFromLot = Math.min(lot.quantity, remainingSold);
    remainingSold -= soldFromLot;
    const remaining = lot.quantity - soldFromLot;
    if (remaining > 0) {
      nextLots.push({ expiryDate: lot.expiryDate, quantity: remaining });
    }
  }

  return nextLots;
};

const groupIgnoresByCoilItemId = (rows: ExpiryIgnoreRow[]): Map<string, ExpiryIgnoreRow[]> => {
  const grouped = new Map<string, ExpiryIgnoreRow[]>();

  for (const row of rows) {
    const expiryDate = row.expiryDate?.trim() ?? '';
    if (!row.coilItemId || !expiryDate) {
      continue;
    }
    const quantity = Math.max(0, Math.floor(row.quantity ?? 0));
    if (quantity <= 0) {
      continue;
    }
    if (!grouped.has(row.coilItemId)) {
      grouped.set(row.coilItemId, []);
    }
    grouped.get(row.coilItemId)!.push({ ...row, expiryDate, quantity });
  }

  for (const rows of grouped.values()) {
    rows.sort((a, b) => a.expiryDate.localeCompare(b.expiryDate));
  }

  return grouped;
};

const applyIgnoresToLots = (lots: PickEntryExpiryLot[], ignores: ExpiryIgnoreRow[]): PickEntryExpiryLot[] => {
  if (!lots.length || !ignores.length) {
    return lots;
  }

  const nextLots = lots
    .map((lot) => ({ ...lot }))
    .sort((a, b) => a.expiryDate.localeCompare(b.expiryDate));

  for (const ignore of ignores) {
    let remaining = Math.max(0, Math.floor(ignore.quantity ?? 0));
    if (remaining <= 0) {
      continue;
    }

    for (const lot of nextLots) {
      if (lot.expiryDate < ignore.expiryDate) {
        continue;
      }
      if (remaining <= 0) {
        break;
      }

      const removed = Math.min(lot.quantity, remaining);
      lot.quantity -= removed;
      remaining -= removed;
    }
  }

  return nextLots.filter((lot) => lot.quantity > 0);
};

const applyIgnoresToRemaining = (
  expiringRemainingByCoilItemIdByDate: Map<string, number>,
  ignoreRows: ExpiryIgnoreRow[],
): Map<string, number> => {
  if (!expiringRemainingByCoilItemIdByDate.size || !ignoreRows.length) {
    return expiringRemainingByCoilItemIdByDate;
  }

  const lotsByCoilItemId = new Map<string, PickEntryExpiryLot[]>();

  for (const [detailKey, quantity] of expiringRemainingByCoilItemIdByDate.entries()) {
    const [coilItemId, expiryDate] = detailKey.split(':');
    if (!coilItemId || !expiryDate) {
      continue;
    }
    const safeQuantity = Math.max(0, Math.floor(quantity));
    if (safeQuantity <= 0) {
      continue;
    }
    if (!lotsByCoilItemId.has(coilItemId)) {
      lotsByCoilItemId.set(coilItemId, []);
    }
    lotsByCoilItemId.get(coilItemId)!.push({ expiryDate, quantity: safeQuantity });
  }

  const ignoreByCoilItemId = groupIgnoresByCoilItemId(ignoreRows);
  const adjusted = new Map<string, number>();

  for (const [coilItemId, lots] of lotsByCoilItemId.entries()) {
    const ignores = ignoreByCoilItemId.get(coilItemId) ?? [];
    const updatedLots = ignores.length ? applyIgnoresToLots(lots, ignores) : lots;

    for (const lot of updatedLots) {
      adjusted.set(`${coilItemId}:${lot.expiryDate}`, lot.quantity);
    }
  }

  return adjusted;
};

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
  const windowStartLabel = getTimezoneDayRange({ timeZone, reference: new Date(), dayOffset: 0 }).label;
  if (runDayRange.label < windowStartLabel) {
    return { warningCount: 0, sections: [] };
  }

  const coilItemIds = Array.from(
    new Set(run.pickEntries.map((entry) => entry.coilItemId).filter((value): value is string => Boolean(value))),
  );

  if (!coilItemIds.length) {
    return { warningCount: 0, sections: [] };
  }

  const plannedByCoilItemId = new Map<string, number>();
  const detailsByCoilItemId = new Map<string, Omit<ExpiringItemsSectionItem, 'quantity'>>();

  run.pickEntries.forEach((entry) => {
    plannedByCoilItemId.set(entry.coilItemId, Math.max(0, resolvePickEntryCount(entry as unknown as PickEntryCountSource)));

    if (!detailsByCoilItemId.has(entry.coilItemId)) {
      detailsByCoilItemId.set(entry.coilItemId, {
        coilItemId: entry.coilItemId,
        sku: {
          id: entry.coilItem.sku.id,
          code: entry.coilItem.sku.code,
          name: entry.coilItem.sku.name,
          type: entry.coilItem.sku.type,
        },
        machine: {
          id: entry.coilItem.coil.machine.id,
          code: entry.coilItem.coil.machine.code,
          description: entry.coilItem.coil.machine.description,
          locationId: entry.coilItem.coil.machine.location?.id ?? null,
          location: entry.coilItem.coil.machine.location
            ? {
                id: entry.coilItem.coil.machine.location.id,
                name: entry.coilItem.coil.machine.location.name,
                address: entry.coilItem.coil.machine.location.address,
              }
            : null,
        },
        coil: {
          id: entry.coilItem.coil.id,
          code: entry.coilItem.coil.code,
        },
      });
    }
  });

  const expiringPickEntries = await prisma.pickEntry.findMany({
    where: {
      coilItemId: { in: coilItemIds },
      run: {
        companyId,
        scheduledFor: {
          not: null,
          lt: runDayRange.end,
        },
      },
      OR: [
        { expiryDate: runDayRange.label },
        { expiryOverrides: { some: { expiryDate: runDayRange.label } } },
      ],
    },
    select: {
      coilItemId: true,
      expiryDate: true,
      count: true,
      override: true,
      current: true,
      par: true,
      need: true,
      forecast: true,
      total: true,
      expiryOverrides: {
        select: {
          expiryDate: true,
          quantity: true,
        },
      },
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
          scheduledFor: true,
        },
      },
    },
  });

  if (!expiringPickEntries.length) {
    return { warningCount: 0, sections: [] };
  }

  let earliestRunAtMs: number | null = null;
  for (const entry of expiringPickEntries) {
    const runAt = entry.run?.scheduledFor?.getTime();
    if (!runAt) {
      continue;
    }
    earliestRunAtMs = earliestRunAtMs === null ? runAt : Math.min(earliestRunAtMs, runAt);
  }

  if (earliestRunAtMs === null) {
    return { warningCount: 0, sections: [] };
  }

  const restockPickEntries = await prisma.pickEntry.findMany({
    where: {
      coilItemId: { in: coilItemIds },
      run: {
        companyId,
        scheduledFor: {
          not: null,
          lt: runDayRange.end,
          gte: new Date(earliestRunAtMs),
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
          scheduledFor: true,
        },
      },
    },
  });

  const restockEntriesByCoilItemId = new Map<string, PlannedRunEntry[]>();

  for (const entry of restockPickEntries) {
    const runAt = entry.run?.scheduledFor?.getTime();
    if (!runAt) {
      continue;
    }
    const plannedQuantity = Math.max(0, resolvePickEntryCount(entry as unknown as PickEntryCountSource));
    if (!restockEntriesByCoilItemId.has(entry.coilItemId)) {
      restockEntriesByCoilItemId.set(entry.coilItemId, []);
    }
    restockEntriesByCoilItemId.get(entry.coilItemId)!.push({ runAtMs: runAt, plannedQuantity });
  }

  const restockIndexByCoilItemId = new Map<string, PlannedIndex>();
  for (const [coilItemId, entries] of restockEntriesByCoilItemId.entries()) {
    restockIndexByCoilItemId.set(coilItemId, buildPlannedIndex(entries));
  }

  const expiringRemainingByCoilItemId = new Map<string, number>();
  for (const entry of expiringPickEntries) {
    const runAt = entry.run?.scheduledFor?.getTime();
    if (!runAt) {
      continue;
    }

    const index = restockIndexByCoilItemId.get(entry.coilItemId) ?? buildPlannedIndex([]);
    const restockedAfter = sumPlannedAfter(index, runAt);

    const plannedCount = Math.max(0, resolvePickEntryCount(entry as unknown as PickEntryCountSource));
    if (plannedCount <= 0) {
      continue;
    }

    const lots = buildExpiryLots({
      baseExpiryDate: entry.expiryDate,
      plannedCount,
      overrides: entry.expiryOverrides,
    });

    const remainingLots = applyRestockConsumption(lots, restockedAfter);
    const remainingForTargetDate = remainingLots
      .filter((lot) => lot.expiryDate === runDayRange.label)
      .reduce((sum, lot) => sum + lot.quantity, 0);

    if (remainingForTargetDate <= 0) {
      continue;
    }

    expiringRemainingByCoilItemId.set(
      entry.coilItemId,
      (expiringRemainingByCoilItemId.get(entry.coilItemId) ?? 0) + remainingForTargetDate,
    );
  }

  const ignoreRows = await prisma.expiryIgnore.findMany({
    where: {
      companyId,
      coilItemId: { in: coilItemIds },
      expiryDate: {
        lte: runDayRange.label,
      },
    },
    select: {
      coilItemId: true,
      expiryDate: true,
      quantity: true,
      ignoredAt: true,
    },
  });

  const ignoredByKey = new Map<string, ExpiryIgnoreRow>();
  for (const row of ignoreRows) {
    const expiryDate = row.expiryDate?.trim() ?? '';
    if (!expiryDate || expiryDate != runDayRange.label) {
      continue;
    }
    ignoredByKey.set(`${row.coilItemId}:${expiryDate}`, row);
  }

  const expiringRemainingByCoilItemIdByDate = new Map<string, number>();
  for (const [coilItemId, expiringRemaining] of expiringRemainingByCoilItemId.entries()) {
    expiringRemainingByCoilItemIdByDate.set(`${coilItemId}:${runDayRange.label}`, expiringRemaining);
  }

  const adjustedByKey = applyIgnoresToRemaining(expiringRemainingByCoilItemIdByDate, ignoreRows);

  const items: ExpiringItemsSectionItem[] = [];
  for (const [detailKey, expiringRemaining] of adjustedByKey.entries()) {
    const [coilItemId] = detailKey.split(':');
    if (!coilItemId || expiringRemaining <= 0) {
      continue;
    }
    const base = detailsByCoilItemId.get(coilItemId);
    if (!base) {
      continue;
    }
    items.push({ ...base, quantity: expiringRemaining, isIgnored: false, ignoredAt: null });
  }

  for (const [detailKey, ignore] of ignoredByKey.entries()) {
    const [coilItemId] = detailKey.split(':');
    if (!coilItemId) {
      continue;
    }
    const base = detailsByCoilItemId.get(coilItemId);
    if (!base) {
      continue;
    }
    items.push({
      ...base,
      quantity: ignore.quantity,
      isIgnored: true,
      ignoredAt: ignore.ignoredAt.toISOString(),
    });
  }

  if (!items.length) {
    return { warningCount: 0, sections: [] };
  }

  items.sort((a, b) => {
    const skuCompare = a.sku.name.localeCompare(b.sku.name);
    if (skuCompare !== 0) {
      return skuCompare;
    }
    const machineCompare = a.machine.code.localeCompare(b.machine.code);
    if (machineCompare !== 0) {
      return machineCompare;
    }
    return a.coil.code.localeCompare(b.coil.code);
  });

  return {
    warningCount: items.filter((item) => !item.isIgnored).length,
    sections: [
      {
        expiryDate: runDayRange.label,
        dayOffset: 0,
        items,
      },
    ],
  };
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

  const expiringPickEntries = await prisma.pickEntry.findMany({
    where: {
      run: {
        companyId,
        scheduledFor: {
          not: null,
          lt: windowEndExclusive.start,
        },
      },
      OR: [
        {
          expiryDate: {
            gte: windowStart.label,
            lte: windowEnd.label,
          },
        },
        {
          expiryOverrides: {
            some: {
              expiryDate: {
                gte: windowStart.label,
                lte: windowEnd.label,
              },
            },
          },
        },
      ],
    },
    select: {
      coilItemId: true,
      expiryDate: true,
      count: true,
      override: true,
      current: true,
      par: true,
      need: true,
      forecast: true,
      total: true,
      expiryOverrides: {
        select: {
          expiryDate: true,
          quantity: true,
        },
      },
      coilItem: {
        select: {
          sku: {
            select: {
              id: true,
              code: true,
              name: true,
              type: true,
              countNeededPointer: true,
            },
          },
          coil: {
            select: {
              id: true,
              code: true,
              machine: {
                select: {
                  id: true,
                  code: true,
                  description: true,
                  location: {
                    select: {
                      id: true,
                      name: true,
                      address: true,
                    },
                  },
                },
              },
            },
          },
        },
      },
      run: {
        select: {
          scheduledFor: true,
        },
      },
    },
  });

  if (!expiringPickEntries.length) {
    return { warningCount: 0, sections: [] };
  }

  const coilItemIds = Array.from(new Set(expiringPickEntries.map((entry) => entry.coilItemId)));

  const ignoreRows = await prisma.expiryIgnore.findMany({
    where: {
      companyId,
      coilItemId: { in: coilItemIds },
      expiryDate: {
        lte: windowEnd.label,
      },
    },
    select: {
      coilItemId: true,
      expiryDate: true,
      quantity: true,
      ignoredAt: true,
    },
  });

  const ignoreRowsForDisplay = ignoreRows.filter((row) => row.expiryDate >= windowStart.label);
  const ignoredByKey = new Map<string, ExpiryIgnoreRow>();

  for (const row of ignoreRowsForDisplay) {
    const expiryDate = row.expiryDate?.trim() ?? '';
    if (!expiryDate) {
      continue;
    }
    ignoredByKey.set(`${row.coilItemId}:${expiryDate}`, row);
  }

  let earliestRunAtMs: number | null = null;
  for (const entry of expiringPickEntries) {
    const runAt = entry.run?.scheduledFor?.getTime();
    if (!runAt) {
      continue;
    }
    earliestRunAtMs = earliestRunAtMs === null ? runAt : Math.min(earliestRunAtMs, runAt);
  }

  if (earliestRunAtMs === null) {
    return { warningCount: 0, sections: [] };
  }

  const restockPickEntries = await prisma.pickEntry.findMany({
    where: {
      coilItemId: { in: coilItemIds },
      run: {
        companyId,
        scheduledFor: {
          not: null,
          lt: windowEndExclusive.start,
          gte: new Date(earliestRunAtMs),
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
          scheduledFor: true,
        },
      },
    },
  });

  const restockEntriesByCoilItemId = new Map<string, PlannedRunEntry[]>();
  for (const entry of restockPickEntries) {
    const runAt = entry.run?.scheduledFor?.getTime();
    if (!runAt) {
      continue;
    }
    const plannedQuantity = Math.max(0, resolvePickEntryCount(entry as unknown as PickEntryCountSource));
    if (!restockEntriesByCoilItemId.has(entry.coilItemId)) {
      restockEntriesByCoilItemId.set(entry.coilItemId, []);
    }
    restockEntriesByCoilItemId.get(entry.coilItemId)!.push({ runAtMs: runAt, plannedQuantity });
  }

  const restockIndexByCoilItemId = new Map<string, PlannedIndex>();
  for (const [coilItemId, entries] of restockEntriesByCoilItemId.entries()) {
    restockIndexByCoilItemId.set(coilItemId, buildPlannedIndex(entries));
  }

  const plannedPickEntriesByDate = await prisma.pickEntry.findMany({
    where: {
      coilItemId: { in: coilItemIds },
      run: {
        companyId,
        scheduledFor: {
          not: null,
          gte: windowStart.start,
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

  const plannedByCoilItemIdByDate = new Map<string, number>();
  const stockingRunByCoilItemIdByDate = new Map<string, { runId: string; runAtMs: number }>();

  for (const entry of plannedPickEntriesByDate) {
    if (!entry.run?.scheduledFor) {
      continue;
    }

    const runDate = getTimezoneDayRange({ timeZone, reference: entry.run.scheduledFor, dayOffset: 0 }).label;
    const key = `${entry.coilItemId}:${runDate}`;
    const plannedQuantity = Math.max(0, resolvePickEntryCount(entry as unknown as PickEntryCountSource));

    plannedByCoilItemIdByDate.set(key, (plannedByCoilItemIdByDate.get(key) ?? 0) + plannedQuantity);

    const runAtMs = entry.run.scheduledFor.getTime();
    const existing = stockingRunByCoilItemIdByDate.get(key);
    if (!existing || runAtMs < existing.runAtMs) {
      stockingRunByCoilItemIdByDate.set(key, { runId: entry.run.id, runAtMs });
    }
  }

  const expiringRemainingByCoilItemIdByDate = new Map<string, number>();
  const detailsByCoilItemId = new Map<string, Omit<ExpiringItemsSectionItem, 'quantity'>>();

  for (const entry of expiringPickEntries) {
    const runAt = entry.run?.scheduledFor?.getTime();
    if (!runAt) {
      continue;
    }

    const index = restockIndexByCoilItemId.get(entry.coilItemId) ?? buildPlannedIndex([]);
    const restockedAfter = sumPlannedAfter(index, runAt);

    const plannedCount = Math.max(0, resolvePickEntryCount(entry as unknown as PickEntryCountSource));
    if (plannedCount <= 0) {
      continue;
    }

    const lots = buildExpiryLots({
      baseExpiryDate: entry.expiryDate,
      plannedCount,
      overrides: entry.expiryOverrides,
    });

    const remainingLots = applyRestockConsumption(lots, restockedAfter).filter(
      (lot) => lot.expiryDate >= windowStart.label && lot.expiryDate <= windowEnd.label,
    );

    for (const lot of remainingLots) {
      const detailKey = `${entry.coilItemId}:${lot.expiryDate}`;
      expiringRemainingByCoilItemIdByDate.set(
        detailKey,
        (expiringRemainingByCoilItemIdByDate.get(detailKey) ?? 0) + lot.quantity,
      );
    }

    if (!detailsByCoilItemId.has(entry.coilItemId)) {
      detailsByCoilItemId.set(entry.coilItemId, {
        coilItemId: entry.coilItemId,
        sku: {
          id: entry.coilItem.sku.id,
          code: entry.coilItem.sku.code,
          name: entry.coilItem.sku.name,
          type: entry.coilItem.sku.type,
        },
        machine: {
          id: entry.coilItem.coil.machine.id,
          code: entry.coilItem.coil.machine.code,
          description: entry.coilItem.coil.machine.description,
          locationId: entry.coilItem.coil.machine.location?.id ?? null,
          location: entry.coilItem.coil.machine.location
            ? {
                id: entry.coilItem.coil.machine.location.id,
                name: entry.coilItem.coil.machine.location.name,
                address: entry.coilItem.coil.machine.location.address,
              }
            : null,
        },
        coil: {
          id: entry.coilItem.coil.id,
          code: entry.coilItem.coil.code,
        },
      });
    }
  }

  const adjustedRemainingByCoilItemIdByDate = applyIgnoresToRemaining(
    expiringRemainingByCoilItemIdByDate,
    ignoreRows,
  );

  const sectionsByDate = new Map<string, UpcomingExpiringItemsSectionItem[]>();

  for (const [detailKey, expiringRemaining] of adjustedRemainingByCoilItemIdByDate.entries()) {
    const [coilItemId, expiryDate] = detailKey.split(':');
    if (!coilItemId || !expiryDate) {
      continue;
    }

    if (ignoredByKey.has(detailKey)) {
      continue;
    }

    const base = detailsByCoilItemId.get(coilItemId);
    if (!base) {
      continue;
    }

    const plannedQuantity = plannedByCoilItemIdByDate.get(detailKey) ?? 0;
    if (expiringRemaining <= 0) {
      continue;
    }

    const stockingRun = stockingRunByCoilItemIdByDate.get(detailKey);

    const item: UpcomingExpiringItemsSectionItem = {
      ...base,
      quantity: expiringRemaining,
      plannedQuantity,
      expiringQuantity: expiringRemaining,
      stockingRun: stockingRun
        ? {
            id: stockingRun.runId,
            runDate: expiryDate,
          }
        : null,
      isIgnored: false,
      ignoredAt: null,
    };

    if (!sectionsByDate.has(expiryDate)) {
      sectionsByDate.set(expiryDate, []);
    }
    sectionsByDate.get(expiryDate)!.push(item);
  }

  for (const [detailKey, ignore] of ignoredByKey.entries()) {
    const [coilItemId, expiryDate] = detailKey.split(':');
    if (!coilItemId || !expiryDate) {
      continue;
    }

    const base = detailsByCoilItemId.get(coilItemId);
    if (!base) {
      continue;
    }

    const plannedQuantity = plannedByCoilItemIdByDate.get(detailKey) ?? 0;
    const stockingRun = stockingRunByCoilItemIdByDate.get(detailKey);

    const item: UpcomingExpiringItemsSectionItem = {
      ...base,
      quantity: ignore.quantity,
      plannedQuantity,
      expiringQuantity: ignore.quantity,
      stockingRun: stockingRun
        ? {
            id: stockingRun.runId,
            runDate: expiryDate,
          }
        : null,
      isIgnored: true,
      ignoredAt: ignore.ignoredAt.toISOString(),
    };

    if (!sectionsByDate.has(expiryDate)) {
      sectionsByDate.set(expiryDate, []);
    }
    sectionsByDate.get(expiryDate)!.push(item);
  }

  const expiryDates = Array.from(sectionsByDate.keys());
  const runs = expiryDates.length
    ? await prisma.run.findMany({
        where: {
          companyId,
          scheduledFor: {
            not: null,
            gte: windowStart.start,
            lt: windowEndExclusive.start,
          },
        },
        select: {
          id: true,
          scheduledFor: true,
          pickEntries: {
            select: {
              coilItem: {
                select: {
                  coil: {
                    select: {
                      machine: {
                        select: {
                          id: true,
                          location: {
                            select: {
                              id: true,
                              name: true,
                              address: true,
                            },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
          locationOrders: {
            select: {
              location: {
                select: {
                  id: true,
                  name: true,
                  address: true,
                },
              },
            },
          },
        },
      })
    : [];

  const runsByDate = new Map<
    string,
    Array<{
      id: string;
      runDate: string;
      locationIds: string[];
      machineIds: string[];
      locations: Array<{ id: string; name: string | null; address: string | null }>;
    }>
  >();

  for (const run of runs) {
    if (!run.scheduledFor) {
      continue;
    }
    const runDate = getTimezoneDayRange({ timeZone, reference: run.scheduledFor, dayOffset: 0 }).label;
    if (!runsByDate.has(runDate)) {
      runsByDate.set(runDate, []);
    }

    const machineIds = new Set<string>();
    const locationsById = new Map<string, { id: string; name: string | null; address: string | null }>();

    for (const pickEntry of run.pickEntries) {
      const machine = pickEntry.coilItem.coil.machine;
      machineIds.add(machine.id);
      if (machine.location) {
        locationsById.set(machine.location.id, machine.location);
      }
    }

    for (const order of run.locationOrders) {
      if (order.location) {
        locationsById.set(order.location.id, order.location);
      }
    }

    const locations = Array.from(locationsById.values());
    const locationIds = locations.map((location) => location.id);

    runsByDate.get(runDate)!.push({
      id: run.id,
      runDate,
      locationIds,
      machineIds: Array.from(machineIds),
      locations,
    });
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
      runs: runsByDate.get(expiryDate) ?? [],
    }))
    .sort((a, b) => a.expiryDate.localeCompare(b.expiryDate));

  const warningCount = sections.reduce(
    (sum, section) => sum + section.items.filter((item) => !item.isIgnored).length,
    0,
  );

  return { warningCount, sections };
}

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
  const windowStartLabel = getTimezoneDayRange({ timeZone, reference: new Date(), dayOffset: 0 }).label;
  if (runDayLabel < windowStartLabel) {
    return null;
  }

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

  const expiringPickEntries = await prisma.pickEntry.findMany({
    where: {
      coilItemId,
      run: {
        companyId,
        scheduledFor: {
          not: null,
          lt: getTimezoneDayRange({ timeZone, reference: run.scheduledFor, dayOffset: 1 }).start,
        },
      },
      OR: [{ expiryDate: runDayLabel }, { expiryOverrides: { some: { expiryDate: runDayLabel } } }],
    },
    select: {
      coilItemId: true,
      expiryDate: true,
      count: true,
      override: true,
      current: true,
      par: true,
      need: true,
      forecast: true,
      total: true,
      expiryOverrides: {
        select: {
          expiryDate: true,
          quantity: true,
        },
      },
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
          scheduledFor: true,
        },
      },
    },
  });

  if (!expiringPickEntries.length) {
    return {
      addedQuantity: 0,
      expiringQuantity: 0,
      coilCode: pickEntry.coilItem.coil.code,
      runDate: runDayLabel,
    };
  }

  let earliestRunAtMs: number | null = null;
  for (const entry of expiringPickEntries) {
    const runAt = entry.run?.scheduledFor?.getTime();
    if (!runAt) {
      continue;
    }
    earliestRunAtMs = earliestRunAtMs === null ? runAt : Math.min(earliestRunAtMs, runAt);
  }

  const restockPickEntries = await prisma.pickEntry.findMany({
    where: {
      coilItemId,
      run: {
        companyId,
        scheduledFor: {
          not: null,
          lt: getTimezoneDayRange({ timeZone, reference: run.scheduledFor, dayOffset: 1 }).start,
          ...(earliestRunAtMs ? { gte: new Date(earliestRunAtMs) } : {}),
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
          scheduledFor: true,
        },
      },
    },
  });

  const plannedEntries: PlannedRunEntry[] = [];
  for (const entry of restockPickEntries) {
    const runAt = entry.run?.scheduledFor?.getTime();
    if (!runAt) {
      continue;
    }
    plannedEntries.push({
      runAtMs: runAt,
      plannedQuantity: Math.max(0, resolvePickEntryCount(entry as unknown as PickEntryCountSource)),
    });
  }

  const index = buildPlannedIndex(plannedEntries);

  let remainingExpiringQuantity = 0;
  for (const entry of expiringPickEntries) {
    const runAt = entry.run?.scheduledFor?.getTime();
    if (!runAt) {
      continue;
    }
    const restockedAfter = sumPlannedAfter(index, runAt);

    const plannedQuantity = Math.max(0, resolvePickEntryCount(entry as unknown as PickEntryCountSource));
    if (plannedQuantity <= 0) {
      continue;
    }

    const lots = buildExpiryLots({
      baseExpiryDate: entry.expiryDate,
      plannedCount: plannedQuantity,
      overrides: entry.expiryOverrides,
    });

    const remainingLots = applyRestockConsumption(lots, restockedAfter);
    remainingExpiringQuantity += remainingLots
      .filter((lot) => lot.expiryDate === runDayLabel)
      .reduce((sum, lot) => sum + lot.quantity, 0);
  }

  const ignoreRows = await prisma.expiryIgnore.findMany({
    where: {
      companyId,
      coilItemId,
      expiryDate: {
        lte: runDayLabel,
      },
    },
    select: {
      quantity: true,
    },
  });

  const ignoredTotal = ignoreRows.reduce((sum, row) => sum + Math.max(0, Math.floor(row.quantity ?? 0)), 0);
  remainingExpiringQuantity = Math.max(0, remainingExpiringQuantity - ignoredTotal);

  if (remainingExpiringQuantity <= 0) {
    return {
      addedQuantity: 0,
      expiringQuantity: remainingExpiringQuantity,
      coilCode: pickEntry.coilItem.coil.code,
      runDate: runDayLabel,
    };
  }

  const overrideCount = Math.max(0, plannedCount) + remainingExpiringQuantity;
  const addedQuantity = remainingExpiringQuantity;

  await prisma.pickEntry.update({
    where: {
      runId_coilItemId: {
        runId,
        coilItemId,
      },
    },
    data: {
      override: overrideCount,
      count: overrideCount,
    },
  });

  await prisma.note.create({
    data: {
      companyId,
      runId,
      machineId: pickEntry.coilItem.coil.machineId,
      body: `Coil ${pickEntry.coilItem.coil.code} has ${remainingExpiringQuantity} items expiring`,
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
