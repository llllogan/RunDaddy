import { Router } from 'express';
import { z } from 'zod';
import { Prisma, PackingSessionStatus as PrismaPackingSessionStatus } from '@prisma/client';
import type { RunStatus as PrismaRunStatus } from '@prisma/client';
import { RunStatus as AppRunStatus, isRunStatus, AuthContext, UserRole } from '../types/enums.js';
import type { RunStatus as RunStatusValue } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { getTimezoneDayRange, isValidTimezone } from '../lib/timezone.js';
import { authenticate } from '../middleware/authenticate.js';
import { requireCompanyContext } from '../middleware/requireCompany.js';
import { setLogConfig } from '../middleware/logging.js';
import { isCompanyManager } from './helpers/authorization.js';
import {
  createRunSchema,
  updateRunSchema,
  createPickEntrySchema,
  updatePickEntrySchema,
  createChocolateBoxSchema,
  updateChocolateBoxSchema,
  runAssignmentSchema,
  ensureMembership,
  ensureRun,
  ensureCoilItem,
  ensureMachine,
} from './helpers/runs.js';
import { parseTimezoneQueryParam, resolveCompanyTimezone } from './helpers/timezone.js';

interface AudioCommand {
  id: string;
  audioCommand: string;
  pickEntryIds: string[];
  type: 'location' | 'machine' | 'item';
  locationId?: string | null;
  locationName?: string;
  locationAddress?: string | null;
  machineName?: string;
  machineId?: string | null;
  machineCode?: string | null;
  machineDescription?: string | null;
  machineTypeName?: string | null;
  skuName?: string;
  skuCode?: string;
  count: number;
  coilCode?: string;
  coilCodes?: string[]; // Array of all coil codes for UI display
  order: number;
}

const router = Router();

const UNASSIGNED_LOCATION_KEY = '__unassigned__';
const CLIENT_UNASSIGNED_LOCATION_KEY = '_unassigned';

const updateLocationOrderSchema = z.object({
  locations: z
    .array(
      z.object({
        locationId: z.string().trim().min(1).optional().nullable(),
        order: z.number().int().nonnegative().optional(),
      }),
    )
    .min(1, 'At least one location is required to save an order.'),
});

const startPackingSessionSchema = z.object({
  categories: z.array(z.string().trim().min(1).nullable()).optional(),
});

const updatePickOverrideSchema = z.object({
  override: z.number().int().min(0).nullable(),
});

const substitutePickEntrySchema = z.object({
  skuId: z.string().trim().min(1),
});

const runsQuerySchema = z.object({
  status: z.string().trim().optional(),
  startDayOffset: z.coerce.number().int().optional(),
  endDayOffset: z.coerce.number().int().optional(),
  timezone: z.string().trim().optional(),
  limit: z.coerce.number().int().optional(),
  offset: z.coerce.number().int().optional(),
});

async function updateRunCompletionStatus(runId: string) {
  const [run, unpickedCount, totalCount] = await prisma.$transaction([
    prisma.run.findUnique({
      where: { id: runId },
      select: { status: true, pickingEndedAt: true },
    }),
    prisma.pickEntry.count({
      where: {
        runId,
        isPicked: false,
      },
    }),
    prisma.pickEntry.count({
      where: { runId },
    }),
  ]);

  if (!run || totalCount === 0 || unpickedCount > 0) {
    return;
  }

  const updateData: Prisma.RunUpdateInput = {};

  if (run.status === AppRunStatus.CREATED || run.status === AppRunStatus.PICKING) {
    updateData.status = AppRunStatus.READY as PrismaRunStatus;
  }

  if (!run.pickingEndedAt) {
    updateData.pickingEndedAt = new Date();
  }

  if (Object.keys(updateData).length === 0) {
    return;
  }

  await prisma.run.update({
    where: { id: runId },
    data: updateData,
  });
}

router.use(authenticate, requireCompanyContext());

// Lists runs for the current company, optionally filtered by status and day offsets.
router.get('/', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const parsedQuery = runsQuerySchema.safeParse(req.query);
  if (!parsedQuery.success) {
    return res.status(400).json({ error: 'Invalid filters supplied', details: parsedQuery.error.flatten() });
  }

  const {
    status,
    startDayOffset,
    endDayOffset,
    timezone,
    limit,
    offset,
  } = parsedQuery.data;

  const effectiveCompanyId = req.auth.companyId as string;

  const timezoneOverride = parseTimezoneQueryParam(timezone);
  if (timezoneOverride && !isValidTimezone(timezoneOverride)) {
    return res.status(400).json({
      error: 'Invalid timezone supplied. Please use an IANA timezone like "America/Chicago".',
    });
  }

  const persistTimezone = req.auth.context === AuthContext.APP;
  const timeZone = await resolveCompanyTimezone(effectiveCompanyId, timezoneOverride, {
    persistIfMissing: persistTimezone,
  });

  const defaultStartOffset = req.auth.role === UserRole.PICKER ? 0 : -100;
  let resolvedStartOffset = startDayOffset ?? defaultStartOffset;
  if (req.auth.role === UserRole.PICKER) {
    resolvedStartOffset = Math.max(resolvedStartOffset, 0);
  } else {
    // Ensure privileged users always get at least the last 100 days by default
    resolvedStartOffset = Math.min(resolvedStartOffset, defaultStartOffset);
  }
  const resolvedEndOffset = endDayOffset;

  if (resolvedEndOffset !== undefined && resolvedEndOffset < resolvedStartOffset) {
    return res
      .status(400)
      .json({ error: 'endDayOffset must be greater than or equal to startDayOffset' });
  }

  const rangeStart = getTimezoneDayRange({ timeZone, dayOffset: resolvedStartOffset }).start;
  const rangeEnd =
    resolvedEndOffset !== undefined
      ? getTimezoneDayRange({ timeZone, dayOffset: resolvedEndOffset }).end
      : undefined;

  const limitNum = Math.min(Math.max(limit ?? 200, 1), 500);
  const offsetNum = Math.max(offset ?? 0, 0);

  const filters: RunRangeFilters = {
    companyId: effectiveCompanyId,
    start: rangeStart,
    limit: limitNum,
    offset: offsetNum,
  };

  if (rangeEnd) {
    filters.end = rangeEnd;
  }

  if (isRunStatus(status)) {
    filters.status = status as unknown as PrismaRunStatus;
  }

  const runs = await fetchRunsWithinRange(filters);

  return res.json(runs);
});

// Get audio commands for a run's packing session
router.post('/:runId/packing-sessions', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { runId } = req.params;
  if (!runId) {
    return res.status(400).json({ error: 'Run ID is required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to start a packing session' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const membership = await ensureMembership(req.auth.companyId, req.auth.userId);
  if (!membership) {
    return res.status(403).json({ error: 'Membership required to start a packing session' });
  }

  const parsedBody = startPackingSessionSchema.safeParse(req.body ?? {});
  if (!parsedBody.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsedBody.error.flatten() });
  }

  const companyTier = await prisma.company.findUnique({
    where: { id: run.companyId },
    select: { tier: { select: { canBreakDownRun: true } } },
  });

  const canBreakDownRun = companyTier?.tier.canBreakDownRun ?? false;

  const normalizedCategories =
    canBreakDownRun && parsedBody.data.categories
      ? parsedBody.data.categories.reduce<Array<string | null>>((acc, category) => {
          const trimmed = category?.trim() ?? '';
          const value = trimmed.length ? trimmed : null;
          if (!acc.includes(value)) {
            acc.push(value);
          }
          return acc;
        }, [])
      : null;

  const includeUncategorized = normalizedCategories?.includes(null) ?? false;
  const categoryValues = normalizedCategories?.filter((value): value is string => Boolean(value)) ?? [];

  try {
    const result = await prisma.$transaction(async (tx) => {
      const session = await tx.packingSession.create({
        data: {
          runId: run.id,
          userId: membership.userId,
        },
      });

      const baseWhere: Prisma.PickEntryWhereInput = {
        runId: run.id,
        isPicked: false,
        OR: [
          { packingSessionId: null },
          {
            packingSession: {
              status: {
                in: [PrismaPackingSessionStatus.FINISHED, PrismaPackingSessionStatus.ABANDONED],
              },
            },
          },
        ],
      };

      const categoryFilters: Prisma.PickEntryWhereInput[] = [];
      if (categoryValues.length > 0) {
        categoryFilters.push({
          coilItem: {
            sku: {
              category: {
                in: categoryValues,
              },
            },
          },
        });
      }

      if (includeUncategorized) {
        categoryFilters.push({
          coilItem: {
            sku: {
              category: null,
            },
          },
        });
      }

      if (categoryFilters.length > 0) {
        const existingAnd = baseWhere.AND;
        const normalizedAnd: Prisma.PickEntryWhereInput[] = Array.isArray(existingAnd)
          ? [...existingAnd]
          : existingAnd
          ? [existingAnd]
          : [];
        normalizedAnd.push({ OR: categoryFilters });
        baseWhere.AND = normalizedAnd;
      }

      const assignmentResult = await tx.pickEntry.updateMany({
        where: baseWhere,
        data: {
          packingSessionId: session.id,
        },
      });

      return { session, assignmentResult };
    });

    return res.status(201).json({
      id: result.session.id,
      runId: result.session.runId,
      userId: result.session.userId,
      startedAt: result.session.startedAt,
      finishedAt: result.session.finishedAt,
      status: result.session.status,
      assignedPickEntries: result.assignmentResult.count,
    });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to start packing session' });
  }
});

router.get('/:runId/packing-sessions/active', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { runId } = req.params;
  if (!runId) {
    return res.status(400).json({ error: 'Run ID is required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to access packing sessions' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const membership = await ensureMembership(req.auth.companyId, req.auth.userId);
  if (!membership) {
    return res.status(403).json({ error: 'Membership required to access packing sessions' });
  }

  const session = await prisma.packingSession.findFirst({
    where: {
      runId: run.id,
      userId: membership.userId,
      status: 'STARTED',
    },
  });

  if (!session) {
    return res.status(404).json({ error: 'No active packing session found' });
  }

  return res.json({
    id: session.id,
    runId: session.runId,
    userId: session.userId,
    startedAt: session.startedAt,
    finishedAt: session.finishedAt,
    status: session.status,
  });
});

router.post('/:runId/packing-sessions/:packingSessionId/abandon', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { runId, packingSessionId } = req.params;
  if (!runId || !packingSessionId) {
    return res.status(400).json({ error: 'Run ID and packingSessionId are required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to stop a packing session' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const membership = await ensureMembership(req.auth.companyId, req.auth.userId);
  if (!membership) {
    return res.status(403).json({ error: 'Membership required to stop a packing session' });
  }

  const packingSession = await prisma.packingSession.findUnique({
    where: { id: packingSessionId },
  });

  if (!packingSession || packingSession.runId !== runId) {
    return res.status(404).json({ error: 'Packing session not found for this run' });
  }

  try {
    const result = await prisma.$transaction(async (tx) => {
      const abandonedSession = await tx.packingSession.update({
        where: { id: packingSessionId },
        data: {
          status: PrismaPackingSessionStatus.ABANDONED,
          finishedAt: new Date(),
        },
      });

      const clearedPickEntries = await tx.pickEntry.updateMany({
        where: {
          packingSessionId: packingSessionId,
        },
        data: {
          packingSessionId: null,
        },
      });

      return { abandonedSession, clearedPickEntries };
    });

    return res.json({
      id: result.abandonedSession.id,
      status: result.abandonedSession.status,
      finishedAt: result.abandonedSession.finishedAt,
      clearedPickEntries: result.clearedPickEntries.count,
    });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to stop packing session' });
  }
});

router.post('/:runId/packing-sessions/:packingSessionId/finish', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { runId, packingSessionId } = req.params;
  if (!runId || !packingSessionId) {
    return res.status(400).json({ error: 'Run ID and packingSessionId are required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to finish a packing session' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const membership = await ensureMembership(req.auth.companyId, req.auth.userId);
  if (!membership) {
    return res.status(403).json({ error: 'Membership required to finish a packing session' });
  }

  const packingSession = await prisma.packingSession.findUnique({
    where: { id: packingSessionId },
  });

  if (!packingSession || packingSession.runId !== runId) {
    return res.status(404).json({ error: 'Packing session not found for this run' });
  }

  try {
    const result = await prisma.$transaction(async (tx) => {
      const finishedSession = await tx.packingSession.update({
        where: { id: packingSessionId },
        data: {
          status: PrismaPackingSessionStatus.FINISHED,
          finishedAt: new Date(),
        },
      });

      const clearedPickEntries = await tx.pickEntry.updateMany({
        where: {
          packingSessionId: packingSessionId,
        },
        data: {
          packingSessionId: null,
        },
      });

      return { finishedSession, clearedPickEntries };
    });

    return res.json({
      id: result.finishedSession.id,
      status: result.finishedSession.status,
      finishedAt: result.finishedSession.finishedAt,
      clearedPickEntries: result.clearedPickEntries.count,
    });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to finish packing session' });
  }
});

router.get('/:runId/audio-commands', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { runId } = req.params;
  if (!runId) {
    return res.status(400).json({ error: 'Run ID is required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to access runs' });
  }

  const { packingSessionId } = req.query;
  if (!packingSessionId || typeof packingSessionId !== 'string') {
    return res.status(400).json({ error: 'packingSessionId is required' });
  }

  const packingSession = await prisma.packingSession.findUnique({
    where: { id: packingSessionId },
  });

  if (!packingSession || packingSession.runId !== runId) {
    return res.status(404).json({ error: 'Packing session not found for this run' });
  }
  const sessionId = packingSession.id;

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const locationOrderMap = new Map<string, number>();
  run.locationOrders.forEach((order) => {
    const key = order.locationId ?? UNASSIGNED_LOCATION_KEY;
    locationOrderMap.set(key, order.position);
  });

  // Get pick entries for this packing session (including already packed), ordered by location, then machine, then coil (largest to smallest)
  const pickEntries = await prisma.pickEntry.findMany({
    where: {
      runId: runId,
      packingSessionId: sessionId,
      count: { gt: 0 }
    },
    include: {
      coilItem: {
        include: {
          coil: {
            include: {
              machine: {
                include: {
                  location: true,
                  machineType: true
                }
              }
            }
          },
          sku: true
        }
      }
    },
    orderBy: [
      { coilItem: { coil: { machine: { location: { name: 'asc' } } } } },
      { coilItem: { coil: { machine: { code: 'asc' } } } },
      { coilItem: { par: 'desc' } }, // Largest par first (largest coil)
      { coilItem: { coil: { code: 'asc' } } },
      { coilItem: { sku: { name: 'asc' } } }
    ]
  });

  // Group by location and machine to create audio commands
  const audioCommands: AudioCommand[] = [];

  // Track unique locations and machines to avoid duplicates
  const uniqueLocations = new Set<string>();
  const uniqueMachines = new Set<string>();

  // Group entries by location and machine
  const groupedEntries = pickEntries.reduce((acc, entry) => {
    const location = entry.coilItem.coil.machine.location;
    const machine = entry.coilItem.coil.machine;
    
    const locationKey = location?.id || UNASSIGNED_LOCATION_KEY;
    const machineKey = machine?.id || 'no-machine';
    
    if (!acc[locationKey]) {
      acc[locationKey] = {
        location: location,
        machines: {}
      };
    }
    
    if (!acc[locationKey].machines[machineKey]) {
      acc[locationKey].machines[machineKey] = {
        machine: machine,
        entries: []
      };
    }
    
    acc[locationKey].machines[machineKey].entries.push(entry);
    return acc;
  }, {} as Record<string, { location: any, machines: Record<string, { machine: any, entries: any[] }> }>);

  // Generate audio commands in the correct order
  let orderCounter = 0;
  const sortedLocationGroups = Object.values(groupedEntries).sort((a, b) => {
    const aKey = a.location?.id ?? UNASSIGNED_LOCATION_KEY;
    const bKey = b.location?.id ?? UNASSIGNED_LOCATION_KEY;
    const aOrder = locationOrderMap.has(aKey) ? locationOrderMap.get(aKey)! : Number.MAX_SAFE_INTEGER;
    const bOrder = locationOrderMap.has(bKey) ? locationOrderMap.get(bKey)! : Number.MAX_SAFE_INTEGER;

    if (aOrder !== bOrder) {
      return aOrder - bOrder;
    }

    const aName = (a.location?.name ?? '').toLowerCase();
    const bName = (b.location?.name ?? '').toLowerCase();
    if (aName === bName) {
      return 0;
    }
    return aName < bName ? -1 : 1;
  });

  const locationGroupsInReverseOrder = [...sortedLocationGroups].reverse();
  locationGroupsInReverseOrder.forEach(locationGroup => {
    // Add location announcement
    const location = locationGroup.location;
    const locationKey = location?.id || UNASSIGNED_LOCATION_KEY;
    if (location && !uniqueLocations.has(locationKey)) {
      uniqueLocations.add(locationKey);
      audioCommands.push({
        id: `location-${locationKey}`,
        audioCommand: `Location ${location.name || 'Unknown'}`,
        pickEntryIds: [],
        type: 'location',
        locationId: location.id ?? null,
        locationName: location.name || 'Unknown',
        locationAddress: location.address ?? null,
        count: 0,
        order: orderCounter++
      });
    }
    
    // Add machine announcements and items for each machine in this location
    Object.values(locationGroup.machines).forEach(machineGroup => {
      const machine = machineGroup.machine;
      const machineKey = machine?.id || 'no-machine';
      
      // Add machine announcement
      if (machine && !uniqueMachines.has(machineKey)) {
        uniqueMachines.add(machineKey);
        audioCommands.push({
          id: `machine-${machineKey}`,
          audioCommand: `Machine ${machine.description || machine.code || 'Unknown'}`,
          pickEntryIds: [],
          type: 'machine',
          locationId: machine.location?.id ?? null,
          locationName: machine.location?.name || location?.name || 'Unknown',
          locationAddress: machine.location?.address ?? null,
          machineId: machine.id ?? null,
          machineName: machine.description || machine.code || 'Unknown',
          machineCode: machine.code ?? null,
          machineDescription: machine.description ?? null,
          machineTypeName: machine.machineType?.description || machine.machineType?.name || null,
          count: 0,
          order: orderCounter++
        });
      }
      
      // Sort entries by coil code lexicographically (E7 -> E6 -> D2 -> D1, etc.)
      const sortedEntries = machineGroup.entries.sort((a, b) => {
        const coilCodeA = a.coilItem.coil?.code || '';
        const coilCodeB = b.coilItem.coil?.code || '';
        
        // Sort lexicographically (E7 -> E6 -> D2 -> D1)
        return coilCodeB.localeCompare(coilCodeA);
      });
      
      // Group entries by SKU within this machine
      const skuGroups = new Map<string, typeof sortedEntries>();
      
      sortedEntries.forEach(entry => {
        const sku = entry.coilItem.sku;
        if (sku) {
          const skuKey = sku.id;
          if (!skuGroups.has(skuKey)) {
            skuGroups.set(skuKey, []);
          }
          skuGroups.get(skuKey)!.push(entry);
        }
      });
      
      // Generate audio commands for each SKU group
      skuGroups.forEach((entries, skuKey) => {
        const firstEntry = entries[0];
        const sku = firstEntry.coilItem.sku;
        const coil = firstEntry.coilItem.coil;
        
        if (sku) {
          const totalCount = entries.reduce((acc, entry) => acc + resolvePickEntryCount(entry), 0);
          
          const skuName = sku.name || 'Unknown item';
          const skuCode = sku.code || '';
          
          // Collect all unique coil codes for this SKU group
          const uniqueCoilCodes = [...new Set(entries.map(entry => entry.coilItem.coil?.code || '').filter(code => code))];
          const coilCount = uniqueCoilCodes.length;
          
          // Build audio command similar to RunDaddy app
          let audioCommand = `${skuName}`;
          if (sku.type && sku.type.trim() && sku.type.toLowerCase() !== 'general') {
            audioCommand += `, ${sku.type}`;
          }
          audioCommand += `. Need ${totalCount}`;
          
          // Announce coil count instead of individual coils
          if (coilCount > 1) {
            audioCommand += `. For ${coilCount} coils`;
          }
          
          // Collect all pick entry IDs for this group
          const pickEntryIds = entries.map(entry => entry.id);
          
          audioCommands.push({
            id: `sku-${skuKey}-${machineKey}`,
            audioCommand: audioCommand,
            pickEntryIds: pickEntryIds,
            type: 'item',
            locationId: machine?.location?.id ?? location?.id ?? null,
            locationName: machine?.location?.name || location?.name || null,
            locationAddress: machine?.location?.address ?? location?.address ?? null,
            machineId: machine?.id ?? null,
            machineName: machine?.description || machine?.code || 'Unknown',
            machineCode: machine?.code ?? null,
            machineDescription: machine?.description ?? null,
            machineTypeName: machine?.machineType?.description || machine?.machineType?.name || null,
            skuName: skuName,
            skuCode: skuCode,
            count: totalCount,
            coilCode: coilCount > 1 ? `${coilCount} coils` : (uniqueCoilCodes[0] || ''),
            coilCodes: uniqueCoilCodes, // Add array of all coil codes for UI display
            order: orderCounter++
          });
        }
      });
    });
  });

  return res.json({
    runId: runId,
    audioCommands: audioCommands,
    totalItems: audioCommands.filter(cmd => cmd.type === 'item').length,
    hasItems: audioCommands.some(cmd => cmd.type === 'item')
  });
});

router.get('/stats', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.json({ totalRuns: 0, averageRunsPerDay: 0 });
  }

  const totalRuns = await prisma.run.count({
    where: {
      companyId: req.auth.companyId,
    },
  });

  const earliestRun = await prisma.run.findFirst({
    where: {
      companyId: req.auth.companyId,
      scheduledFor: { not: null },
    },
    orderBy: { scheduledFor: 'asc' },
    select: { scheduledFor: true },
  });

  let averageRunsPerDay = 0;

  if (earliestRun?.scheduledFor) {
    const now = new Date();
    const start = earliestRun.scheduledFor;
    const millisecondsInDay = 1000 * 60 * 60 * 24;
    const daysActive = Math.max(1, Math.ceil((now.getTime() - start.getTime()) / millisecondsInDay));
    averageRunsPerDay = totalRuns / daysActive;
  }

  return res.json({ totalRuns, averageRunsPerDay });
});

// Get all runs for the company (or all companies for lighthouse)
router.get('/all', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const effectiveCompanyId = req.auth.companyId;

  const { limit = 50, offset = 0 } = req.query;
  const limitNum = Math.min(Number(limit) || 50, 200); // Cap at 200 runs
  const offsetNum = Number(offset) || 0;

  // Use the same view as the daily endpoints for consistency
  const rows = await prisma.$queryRaw<RunDailyLocationRow[]>(
    Prisma.sql`
      SELECT
        run_id,
        company_id,
        company_name,
        scheduled_date,
        scheduled_for,
        run_status,
        picking_started_at,
        picking_ended_at,
        run_created_at,
        runner_id,
        runner_first_name,
        runner_last_name,
        location_count
      FROM v_run_daily_locations
      WHERE company_id = ${effectiveCompanyId}
      ORDER BY scheduled_for DESC, run_created_at DESC
      LIMIT ${limitNum}
      OFFSET ${offsetNum}
    `
  );

  const runs = await buildRunResponses(rows);

  return res.json(runs);
});

// Get runs scheduled for tomorrow with a status of READY
router.get('/tomorrow/ready', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.json([]);
  }

  const timezoneOverride = parseTimezoneQueryParam(req.query.timezone);
  if (timezoneOverride && !isValidTimezone(timezoneOverride)) {
    return res.status(400).json({
      error: 'Invalid timezone supplied. Please use an IANA timezone like "America/Chicago".',
    });
  }

  const persistTimezone = req.auth.context === AuthContext.APP;
  const timeZone = await resolveCompanyTimezone(req.auth.companyId, timezoneOverride, {
    persistIfMissing: persistTimezone,
  });
  const { start, end } = getTimezoneDayRange({ timeZone, dayOffset: 1 });

  const runs = await prisma.run.findMany({
    where: {
      companyId: req.auth.companyId,
      scheduledFor: {
        gte: start,
        lt: end,
      },
      status: AppRunStatus.READY,
    },
    orderBy: { scheduledFor: 'asc' },
    include: {
      runner: true,
    },
  });

  return res.json(runs);
});

router.get('/:runId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { runId } = req.params;
  if (!runId) {
    return res.status(400).json({ error: 'Run ID is required' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to access runs' });
  }

  const payload = await getRunDetailPayload(req.auth.companyId, runId);
  if (!payload) {
    return res.status(404).json({ error: 'Run not found' });
  }

  return res.json(payload);
});

router.put('/:runId/location-order', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to update location ordering' });
  }

  const { runId } = req.params;
  if (!runId) {
    return res.status(400).json({ error: 'Run ID is required' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const parsed = updateLocationOrderSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const normalizedLocations = parsed.data.locations
    .map((entry, index) => ({
      locationId: entry.locationId ?? null,
      order: typeof entry.order === 'number' ? entry.order : index,
      originalIndex: index,
    }))
    .sort((a, b) => {
      if (a.order === b.order) {
        return a.originalIndex - b.originalIndex;
      }
      return a.order - b.order;
    })
    .reduce<Array<string | null>>((acc, entry) => {
      const key = entry.locationId ?? UNASSIGNED_LOCATION_KEY;
      if (acc.find((candidate) => (candidate ?? UNASSIGNED_LOCATION_KEY) === key)) {
        return acc;
      }
      acc.push(entry.locationId);
      return acc;
    }, []);

  const updatedOrders = await prisma.$transaction(async (tx) => {
    await tx.runLocationOrder.deleteMany({ where: { runId } });

    if (normalizedLocations.length) {
      await tx.runLocationOrder.createMany({
        data: normalizedLocations.map((locationId, index) => ({
          runId,
          locationId,
          position: index,
        })),
      });
    }

    return tx.runLocationOrder.findMany({
      where: { runId },
      include: { location: true },
      orderBy: { position: 'asc' },
    });
  });

  const serializedOrders = updatedOrders.map((order) => ({
    id: order.id,
    locationId: order.locationId,
    position: order.position,
    location: order.location
      ? {
          id: order.location.id,
          name: order.location.name,
          address: order.location.address,
        }
      : null,
  }));

  return res.json({ locationOrders: serializedOrders });
});

// Assigns or unassigns a runner to a run.
router.post('/:runId/assignment', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to assign runs' });
  }

  const runId = req.params.runId?.trim() || '';

  const parsed = runAssignmentSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  // If userId is provided, validate membership and permissions
  if (parsed.data.userId) {
    const membership = await ensureMembership(req.auth.companyId, parsed.data.userId);
    if (!membership) {
      return res.status(404).json({ error: 'User not found in company' });
    }

    const isSelfAssignment = parsed.data.userId === req.auth.userId;
    const isManager = isCompanyManager(req.auth.role);

    // TODO: Check how I want this logic to go down
    // if (!isManager && !isSelfAssignment) {
    //   return res.status(403).json({ error: 'Insufficient permissions to assign runs' });
    // }

    // For self-assignment, check if the role is already taken
    if (isSelfAssignment && !isManager) {
      const isRunnerTaken = run.runnerId != null && run.runnerId !== req.auth.userId;
      if (isRunnerTaken) {
        return res.status(409).json({ error: 'Runner role is already assigned to another user' });
      }
    }
  } 
  // else {
  //   // For unassignment, only managers can unassign users
  //   if (!isCompanyManager(req.auth.role)) {
  //     return res.status(403).json({ error: 'Insufficient permissions to unassign runs' });
  //   }
  // }

  const userId = parsed.data.userId && parsed.data.userId.trim() !== "" ? parsed.data.userId : null;
  const updateData = { runnerId: userId };

  const updatedRun = await prisma.run.update({
    where: { id: run.id },
    data: updateData,
    include: {
      runner: true,
    },
  });

  return res.status(200).json({
    id: updatedRun.id,
    companyId: updatedRun.companyId,
    status: updatedRun.status,
  });
});

// Updates a run status
router.patch('/:runId/status', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to update runs' });
  }

  const { runId } = req.params;
  const { status } = req.body;
  
  if (!runId) {
    return res.status(400).json({ error: 'Run ID is required' });
  }

  if (!status || !isRunStatus(status)) {
    return res.status(400).json({ error: 'Invalid status. Must be one of: CREATED, PENDING_FRESH, PICKING, READY' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  // Only managers can update run status
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update run status' });
  }

  // Prepare update data
  const updateData: Prisma.RunUpdateInput = { status: status as PrismaRunStatus };
  
  // Set pickingEndedAt when status changes to PENDING_FRESH or READY, only if not already set
  if ((status === 'PENDING_FRESH' || status === 'READY') && !run.pickingEndedAt) {
    updateData.pickingEndedAt = new Date();
  }

  const updatedRun = await prisma.run.update({
    where: { id: run.id },
    data: updateData,
    include: {
      runner: true,
    },
  });

  return res.status(200).json({
    id: updatedRun.id,
    status: updatedRun.status,
  });
});

// Bulk update pick entries picked flag
router.patch('/:runId/picks/status', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to update picks' });
  }

  const { runId } = req.params;
  if (!runId) {
    return res.status(400).json({ error: 'Run ID is required' });
  }

  const { pickIds, isPicked } = req.body;

  if (!Array.isArray(pickIds)) {
    return res.status(400).json({ error: 'Pick IDs array is required' });
  }

  const normalizedPickIds = Array.from(new Set(pickIds))
    .filter((id): id is string => typeof id === 'string' && id.trim().length > 0);

  if (normalizedPickIds.length === 0) {
    return res.status(400).json({ error: 'Pick IDs array is required' });
  }

  if (typeof isPicked !== 'boolean') {
    return res.status(400).json({ error: 'isPicked must be a boolean' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const updateData: Prisma.PickEntryUpdateManyMutationInput = {
    isPicked,
    pickedAt: isPicked ? new Date() : null,
  };

  const updatedPickEntries = await prisma.pickEntry.updateMany({
    where: {
      id: { in: normalizedPickIds },
      runId: runId
    },
    data: updateData
  });

  if (updatedPickEntries.count === 0) {
    return res.status(404).json({ error: 'No pick entries were updated' });
  }

  // If picks were marked as picked for the first time on this run, set pickingStartedAt
  if (isPicked && !run.pickingStartedAt) {
    await prisma.run.update({
      where: { id: run.id },
      data: { 
        pickingStartedAt: new Date(),
        ...(run.status === 'CREATED' && { status: 'PICKING' })
      }
    });
  }

  await updateRunCompletionStatus(run.id);

  return res.json({
    updatedCount: updatedPickEntries.count,
  });
});

router.patch('/:runId/picks/:pickId/override', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to update pick overrides' });
  }

  const { runId, pickId } = req.params;
  if (!runId || !pickId) {
    return res.status(400).json({ error: 'Run ID and Pick ID are required' });
  }

  const parsed = updatePickOverrideSchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const pickEntry = run.pickEntries.find((entry) => entry.id === pickId);
  if (!pickEntry) {
    return res.status(404).json({ error: 'Pick entry not found' });
  }

  const overrideValue = parsed.data.override;
  const fallbackCount =
    pickEntry.total ??
    pickEntry.need ??
    pickEntry.forecast ??
    pickEntry.par ??
    pickEntry.current ??
    pickEntry.count;
  const nextCount = overrideValue === null ? resolvePointerCount(pickEntry, fallbackCount) : overrideValue;

  const updated = await prisma.pickEntry.update({
    where: { id: pickEntry.id },
    data: {
      override: overrideValue,
      count: nextCount,
    },
    select: {
      id: true,
      runId: true,
      count: true,
      override: true,
    },
  });

  return res.json({
    id: updated.id,
    runId: updated.runId,
    count: updated.count,
    override: updated.override,
  });
});

router.patch('/:runId/picks/:pickId/substitute', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to substitute pick SKUs' });
  }

  const { runId, pickId } = req.params;
  if (!runId || !pickId) {
    return res.status(400).json({ error: 'Run ID and Pick ID are required' });
  }

  const parsed = substitutePickEntrySchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const pickEntry = run.pickEntries.find((entry) => entry.id === pickId);
  if (!pickEntry) {
    return res.status(404).json({ error: 'Pick entry not found' });
  }

  const sku = await prisma.sKU.findFirst({
    where: { id: parsed.data.skuId, companyId: req.auth.companyId },
    select: { id: true },
  });
  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }

  if (pickEntry.coilItem.skuId === sku.id) {
    return res.json({ id: pickEntry.id, runId: pickEntry.runId, coilItemId: pickEntry.coilItemId });
  }

  const nextCoilItem = await prisma.coilItem.upsert({
    where: {
      coilId_skuId: {
        coilId: pickEntry.coilItem.coilId,
        skuId: sku.id,
      },
    },
    update: {},
    create: {
      coilId: pickEntry.coilItem.coilId,
      skuId: sku.id,
      par: pickEntry.coilItem.par,
    },
    select: { id: true },
  });

  try {
    const updated = await prisma.pickEntry.update({
      where: { id: pickEntry.id },
      data: { coilItemId: nextCoilItem.id },
      select: { id: true, runId: true, coilItemId: true },
    });

    return res.json(updated);
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      return res.status(409).json({ error: 'A pick entry already exists for that coil and SKU.' });
    }
    throw error;
  }
});

// Delete a pick entry from a run
router.delete('/:runId/picks/:pickId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to delete pick entries' });
  }

  const { runId, pickId } = req.params;
  if (!runId || !pickId) {
    return res.status(400).json({ error: 'Run ID and Pick ID are required' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const pickEntry = await prisma.pickEntry.findFirst({
    where: {
      id: pickId,
      runId: runId
    }
  });

  if (!pickEntry) {
    return res.status(404).json({ error: 'Pick entry not found' });
  }

  await prisma.pickEntry.delete({
    where: { id: pickEntry.id }
  });

  await updateRunCompletionStatus(run.id);

  return res.status(204).send();
});

router.delete('/:runId/locations/:locationId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to delete picks by location' });
  }

  const { runId, locationId } = req.params;
  const normalizedRunId = runId?.trim();
  const normalizedLocationId = locationId?.trim();

  if (!normalizedRunId) {
    return res.status(400).json({ error: 'Run ID is required' });
  }

  if (!normalizedLocationId) {
    return res.status(400).json({ error: 'Location ID is required' });
  }

  const run = await ensureRun(req.auth.companyId, normalizedRunId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const isUnassigned =
    normalizedLocationId === CLIENT_UNASSIGNED_LOCATION_KEY || normalizedLocationId === UNASSIGNED_LOCATION_KEY;

  if (!isUnassigned) {
    const location = await prisma.location.findUnique({
      where: { id: normalizedLocationId },
      select: { id: true, companyId: true },
    });

    if (!location || location.companyId !== req.auth.companyId) {
      return res.status(404).json({ error: 'Location not found' });
    }
  }

  const deleteWhere: Prisma.PickEntryWhereInput = isUnassigned
    ? {
        runId: normalizedRunId,
        coilItem: {
          coil: {
            machine: {
              locationId: null,
            },
          },
        },
      }
    : {
        runId: normalizedRunId,
        coilItem: {
          coil: {
            machine: {
              locationId: normalizedLocationId,
            },
          },
        },
      };

  const { deletedCount } = await prisma.$transaction(async (tx) => {
    const deleted = await tx.pickEntry.deleteMany({
      where: deleteWhere,
    });

    await tx.runLocationOrder.deleteMany({
      where: {
        runId: normalizedRunId,
        locationId: isUnassigned ? null : normalizedLocationId,
      },
    });

    return { deletedCount: deleted.count };
  });

  await updateRunCompletionStatus(run.id);

  return res.json({ deletedCount });
});

// Deletes a run and all related records.
router.delete('/:runId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to delete runs' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to delete runs' });
  }

  const run = await ensureRun(req.auth.companyId, req.params.runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  await prisma.run.delete({ where: { id: run.id } });
  return res.status(204).send();
});

// Chocolate Boxes endpoints

// Get all chocolate boxes for a run
router.get('/:runId/chocolate-boxes', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to access chocolate boxes' });
  }

  const { runId } = req.params;
  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const chocolateBoxes = await prisma.chocolateBox.findMany({
    where: { runId },
    include: {
      machine: {
        include: {
          location: true,
          machineType: true,
        },
      },
    },
    orderBy: { number: 'asc' },
  });

  return res.json(chocolateBoxes.map(box => ({
    id: box.id,
    number: box.number,
    machine: box.machine ? {
      id: box.machine.id,
      code: box.machine.code,
      description: box.machine.description,
      machineType: box.machine.machineType ? {
        id: box.machine.machineType.id,
        name: box.machine.machineType.name,
        description: box.machine.machineType.description,
      } : null,
      location: box.machine.location ? {
        id: box.machine.location.id,
        name: box.machine.location.name,
        address: box.machine.location.address,
      } : null,
    } : null,
  })));
});

// Create a new chocolate box for a run
router.post('/:runId/chocolate-boxes', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to create chocolate boxes' });
  }

  const { runId } = req.params;
  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const parsed = createChocolateBoxSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  // Check if machine belongs to the company
  const machine = await ensureMachine(req.auth.companyId, parsed.data.machineId);
  if (!machine) {
    return res.status(404).json({ error: 'Machine not found' });
  }

  // Check if chocolate box number already exists for this run
  const existingBox = await prisma.chocolateBox.findUnique({
    where: {
      runId_number: {
        runId,
        number: parsed.data.number,
      },
    },
  });

  if (existingBox) {
    return res.status(409).json({ error: 'Chocolate box number already exists for this run' });
  }

  const chocolateBox = await prisma.chocolateBox.create({
    data: {
      runId,
      machineId: parsed.data.machineId,
      number: parsed.data.number,
    },
    include: {
      machine: {
        include: {
          location: true,
          machineType: true,
        },
      },
    },
  });

  return res.status(201).json({
    id: chocolateBox.id,
    number: chocolateBox.number,
    machine: chocolateBox.machine ? {
      id: chocolateBox.machine.id,
      code: chocolateBox.machine.code,
      description: chocolateBox.machine.description,
      machineType: chocolateBox.machine.machineType ? {
        id: chocolateBox.machine.machineType.id,
        name: chocolateBox.machine.machineType.name,
        description: chocolateBox.machine.machineType.description,
      } : null,
      location: chocolateBox.machine.location ? {
        id: chocolateBox.machine.location.id,
        name: chocolateBox.machine.location.name,
        address: chocolateBox.machine.location.address,
      } : null,
    } : null,
  });
});

// Update a chocolate box
router.patch('/:runId/chocolate-boxes/:boxId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to update chocolate boxes' });
  }

  const { runId, boxId } = req.params;
  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const parsed = updateChocolateBoxSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  // Check if chocolate box exists and belongs to the run
  const existingBox = await prisma.chocolateBox.findFirst({
    where: {
      id: boxId,
      runId,
    },
  });

  if (!existingBox) {
    return res.status(404).json({ error: 'Chocolate box not found' });
  }

  // If updating machine, check if it belongs to the company
  if (parsed.data.machineId) {
    const machine = await ensureMachine(req.auth.companyId, parsed.data.machineId);
    if (!machine) {
      return res.status(404).json({ error: 'Machine not found' });
    }
  }

  // If updating number, check if it already exists for this run (excluding this box)
  if (parsed.data.number) {
    const duplicateBox = await prisma.chocolateBox.findFirst({
      where: {
        runId,
        number: parsed.data.number,
        id: { not: boxId },
      },
    });

    if (duplicateBox) {
      return res.status(409).json({ error: 'Chocolate box number already exists for this run' });
    }
  }

  const chocolateBox = await prisma.chocolateBox.update({
    where: { id: boxId },
    data: parsed.data as Prisma.ChocolateBoxUpdateInput,
    include: {
      machine: {
        include: {
          location: true,
          machineType: true,
        },
      },
    },
  });

  return res.json({
    id: chocolateBox.id,
    number: chocolateBox.number,
    machine: chocolateBox.machine ? {
      id: chocolateBox.machine.id,
      code: chocolateBox.machine.code,
      description: chocolateBox.machine.description,
      machineType: chocolateBox.machine.machineType ? {
        id: chocolateBox.machine.machineType.id,
        name: chocolateBox.machine.machineType.name,
        description: chocolateBox.machine.machineType.description,
      } : null,
      location: chocolateBox.machine.location ? {
        id: chocolateBox.machine.location.id,
        name: chocolateBox.machine.location.name,
        address: chocolateBox.machine.location.address,
      } : null,
    } : null,
  });
});

// Delete a chocolate box
router.delete('/:runId/chocolate-boxes/:boxId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to delete chocolate boxes' });
  }

  const { runId, boxId } = req.params;
  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  // Check if chocolate box exists and belongs to the run
  const existingBox = await prisma.chocolateBox.findFirst({
    where: {
      id: boxId,
      runId,
    },
  });

  if (!existingBox) {
    return res.status(404).json({ error: 'Chocolate box not found' });
  }

  await prisma.chocolateBox.delete({
    where: { id: boxId },
  });

  return res.status(204).send();
});

type RunDetailSource = NonNullable<Awaited<ReturnType<typeof ensureRun>>>;

type LocationPayload = {
  id: string;
  name: string | null;
  address: string | null;
};

type LocationOrderPayload = {
  id: string;
  locationId: string | null;
  position: number;
  location: LocationPayload | null;
};

type MachineTypePayload = {
  id: string;
  name: string;
  description: string | null;
} | null;

type MachinePayload = {
  id: string;
  code: string;
  description: string | null;
  machineType: MachineTypePayload;
  location: LocationPayload | null;
};

type PickItemPayload = {
  id: string;
  count: number;
  override: number | null;
  current: number | null;
  par: number | null;
  need: number | null;
  forecast: number | null;
  total: number | null;
  isPicked: boolean;
  pickedAt: Date | null;
  packingSessionId: string | null;
  coilItem: {
    id: string;
    par: number;
  };
  coil: {
    id: string;
    code: string;
    machineId: string | null;
  };
  sku: null | {
    id: string;
    code: string;
    name: string;
    type: string;
    category: string | null;
    weight: number | null;
    labelColour: string | null;
    isFreshOrFrozen: boolean;
  };
  machine: MachinePayload | null;
  location: LocationPayload | null;
};

type RunDetailPayload = {
  id: string;
  status: PrismaRunStatus;
  companyId: string;
  scheduledFor: Date | null;
  pickingStartedAt: Date | null;
  pickingEndedAt: Date | null;
  createdAt: Date;
  runner: null | {
    id: string;
    firstName: string | null;
    lastName: string | null;
  };
  locations: LocationPayload[];
  machines: MachinePayload[];
  pickItems: PickItemPayload[];
  pickEntries: Array<{
    id: string;
    count: number;
    override: number | null;
    current: number | null;
    par: number | null;
    need: number | null;
    forecast: number | null;
    total: number | null;
    isPicked: boolean;
    pickedAt: Date | null;
    coilItem: {
      id: string;
      par: number;
      coil: {
        id: string;
        code: string;
        machine: MachinePayload | null;
      };
      sku: PickItemPayload['sku'];
    };
  }>;
  packers: Array<{
    id: string;
    firstName: string | null;
    lastName: string | null;
    email: string | null;
    sessionCount: number;
  }>;
  chocolateBoxes: Array<{
    id: string;
    number: number;
    machine: MachinePayload | null;
  }>;
  locationOrders: LocationOrderPayload[];
};

type PickEntryCountSource = {
  count: number;
  override: number | null;
  current: number | null;
  par: number | null;
  need: number | null;
  forecast: number | null;
  total: number | null;
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

function buildRunDetailPayload(run: RunDetailSource): RunDetailPayload {
  const machinesById = new Map<string, MachinePayload>();
  const locationsById = new Map<string, LocationPayload>();
  const packersById = new Map<
    string,
    {
      id: string;
      firstName: string | null;
      lastName: string | null;
      email: string | null;
      sessionCount: number;
    }
  >();

  const serializeLocation = (
    location: RunDetailSource['pickEntries'][number]['coilItem']['coil']['machine']['location'],
  ): LocationPayload | null => {
    if (!location) {
      return null;
    }

    const existing = locationsById.get(location.id);
    if (existing) {
      return existing;
    }

    const serialized: LocationPayload = {
      id: location.id,
      name: location.name,
      address: location.address,
    };
    locationsById.set(location.id, serialized);
    return serialized;
  };

  const serializeMachine = (
    machine: RunDetailSource['pickEntries'][number]['coilItem']['coil']['machine'] | null | undefined,
  ): MachinePayload | null => {
    if (!machine) {
      return null;
    }

    const existing = machinesById.get(machine.id);
    if (existing) {
      return existing;
    }

    const serialized: MachinePayload = {
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
      location: serializeLocation(machine.location),
    };

    machinesById.set(machine.id, serialized);
    return serialized;
  };

  const pickItems: PickItemPayload[] = run.pickEntries.map((entry) => {
    const machine = entry.coilItem.coil.machine;
    const serializedMachine = serializeMachine(machine);
    const serializedLocation = machine ? serializeLocation(machine.location) : null;

    const calculatedCount = resolvePickEntryCount(entry);

    return {
      id: entry.id,
      count: calculatedCount,
      override: entry.override ?? null,
      current: entry.current,
      par: entry.par,
      need: entry.need,
      forecast: entry.forecast,
      total: entry.total,
      isPicked: !!entry.isPicked,
      pickedAt: entry.pickedAt,
      packingSessionId: entry.packingSessionId,
      coilItem: {
        id: entry.coilItem.id,
        par: entry.coilItem.par,
      },
      coil: {
        id: entry.coilItem.coil.id,
        code: entry.coilItem.coil.code,
        machineId: machine?.id ?? null,
      },
      sku: entry.coilItem.sku
        ? {
            id: entry.coilItem.sku.id,
            code: entry.coilItem.sku.code,
            name: entry.coilItem.sku.name,
            type: entry.coilItem.sku.type,
            category: entry.coilItem.sku.category,
            weight: entry.coilItem.sku.weight,
            labelColour: entry.coilItem.sku.labelColour,
            isFreshOrFrozen: entry.coilItem.sku.isFreshOrFrozen,
          }
        : null,
      machine: serializedMachine,
      location: serializedLocation,
    };
  });

  run.packingSessions.forEach((session) => {
    const user = session.user;
    if (!user) {
      return;
    }

    const existing = packersById.get(user.id) ?? {
      id: user.id,
      firstName: user.firstName,
      lastName: user.lastName,
      email: user.email,
      sessionCount: 0,
    };

    existing.sessionCount += 1;
    packersById.set(user.id, existing);
  });

  const chocolateBoxes = run.chocolateBoxes.map((box) => ({
    id: box.id,
    number: box.number,
    machine: serializeMachine(box.machine),
  }));

  const locationOrders = run.locationOrders
    .map((order) => ({
      id: order.id,
      locationId: order.locationId,
      position: order.position,
      location: serializeLocation(order.location),
    }))
    .sort((a, b) => a.position - b.position);

  return {
    id: run.id,
    status: run.status,
    companyId: run.companyId,
    scheduledFor: run.scheduledFor,
    pickingStartedAt: run.pickingStartedAt,
    pickingEndedAt: run.pickingEndedAt,
    createdAt: run.createdAt,
    runner: run.runner
      ? {
          id: run.runner.id,
          firstName: run.runner.firstName,
          lastName: run.runner.lastName,
        }
      : null,
    locations: Array.from(locationsById.values()),
    machines: Array.from(machinesById.values()),
    pickItems,
  pickEntries: run.pickEntries.map((entry) => {
      const calculatedCount = resolvePickEntryCount(entry);

      return {
        id: entry.id,
        count: calculatedCount,
        override: entry.override ?? null,
        current: entry.current,
        par: entry.par,
        need: entry.need,
        forecast: entry.forecast,
        total: entry.total,
        isPicked: !!entry.isPicked,
        pickedAt: entry.pickedAt,
        packingSessionId: entry.packingSessionId,
      coilItem: {
        id: entry.coilItem.id,
        par: entry.coilItem.par,
        coil: {
          id: entry.coilItem.coil.id,
          code: entry.coilItem.coil.code,
          machine: serializeMachine(entry.coilItem.coil.machine),
        },
        sku: entry.coilItem.sku
          ? {
              id: entry.coilItem.sku.id,
              code: entry.coilItem.sku.code,
              name: entry.coilItem.sku.name,
              type: entry.coilItem.sku.type,
              category: entry.coilItem.sku.category,
              weight: entry.coilItem.sku.weight,
              labelColour: entry.coilItem.sku.labelColour,
              isFreshOrFrozen: entry.coilItem.sku.isFreshOrFrozen,
            }
          : null,
      },
    };
    }),
    packers: Array.from(packersById.values()).sort((first, second) => {
      const normalizedName = (packer: { firstName: string | null; lastName: string | null; email: string | null; id: string }) => {
        const combined = `${packer.firstName ?? ''} ${packer.lastName ?? ''}`.trim();
        if (combined.length > 0) {
          return combined.toLowerCase();
        }
        const trimmedEmail = (packer.email ?? '').trim();
        if (trimmedEmail.length > 0) {
          return trimmedEmail.toLowerCase();
        }
        return packer.id.toLowerCase();
      };

      return normalizedName(first).localeCompare(normalizedName(second), undefined, { sensitivity: 'base' });
    }),
    chocolateBoxes,
    locationOrders,
  };
}

export async function getRunDetailPayload(companyId: string, runId: string): Promise<RunDetailPayload | null> {
  const run = await ensureRun(companyId, runId);
  if (!run) {
    return null;
  }

  return buildRunDetailPayload(run);
}

type RunDailyLocationRow = {
  run_id: string;
  company_id: string;
  company_name: string;
  scheduled_date: Date | string | null;
  scheduled_for: Date | null;
  run_status: PrismaRunStatus;
  picking_started_at: Date | null;
  picking_ended_at: Date | null;
  run_created_at: Date;
  runner_id: string | null;
  runner_first_name: string | null;
  runner_last_name: string | null;
  location_count: bigint | number | string | null;
};

type RunDailyResponse = {
  id: string;
  companyId: string;
  status: PrismaRunStatus;
  scheduledFor: Date | null;
  pickingStartedAt: Date | null;
  pickingEndedAt: Date | null;
  createdAt: Date;
  runnerId: string | null;
  locationCount: number;
  chocolateBoxes: Array<{
    id: string;
    number: number;
    machine: {
      id: string;
      code: string;
      description: string | null;
      machineType: {
        id: string;
        name: string;
        description: string | null;
      } | null;
      location: {
        id: string;
        name: string | null;
        address: string | null;
      } | null;
    } | null;
  }>;
  runner: null | {
    id: string;
    firstName: string | null;
    lastName: string | null;
  };
};

type RunRangeFilters = {
  companyId: string;
  start: Date;
  end?: Date;
  status?: PrismaRunStatus;
  limit: number;
  offset: number;
};

async function fetchRunsWithinRange(filters: RunRangeFilters): Promise<RunDailyResponse[]> {
  const endCondition = filters.end ? Prisma.sql`AND scheduled_for < ${filters.end}` : Prisma.sql``;
  const statusCondition = filters.status ? Prisma.sql`AND run_status = ${filters.status}` : Prisma.sql``;

  const rows = await prisma.$queryRaw<RunDailyLocationRow[]>(
    Prisma.sql`
      SELECT
        run_id,
        company_id,
        company_name,
        scheduled_date,
        scheduled_for,
        run_status,
        picking_started_at,
        picking_ended_at,
        run_created_at,
        runner_id,
        runner_first_name,
        runner_last_name,
        location_count
      FROM v_run_daily_locations
      WHERE company_id = ${filters.companyId}
        AND scheduled_for >= ${filters.start}
        ${endCondition}
        ${statusCondition}
      ORDER BY scheduled_for ASC, run_created_at ASC
      LIMIT ${filters.limit}
      OFFSET ${filters.offset}
    `,
  );

  return buildRunResponses(rows);
}

async function buildRunResponses(rows: RunDailyLocationRow[]): Promise<RunDailyResponse[]> {
  if (!rows.length) {
    return [];
  }

  const runIds = rows.map((row) => row.run_id);
  const chocolateBoxes =
    runIds.length > 0
      ? await prisma.chocolateBox.findMany({
          where: {
            runId: { in: runIds },
          },
          include: {
            machine: {
              include: {
                location: true,
                machineType: true,
              },
            },
          },
          orderBy: {
            number: 'asc',
          },
        })
      : [];

  const chocolateBoxesByRun = new Map<string, Array<{ id: string; number: number; machine: any }>>();
  chocolateBoxes.forEach((box) => {
    if (!chocolateBoxesByRun.has(box.runId)) {
      chocolateBoxesByRun.set(box.runId, []);
    }
    chocolateBoxesByRun.get(box.runId)!.push({
      id: box.id,
      number: box.number,
      machine: box.machine,
    });
  });

  return rows.map((row) => ({
    id: row.run_id,
    companyId: row.company_id,
    status: row.run_status,
    scheduledFor: row.scheduled_for,
    pickingStartedAt: row.picking_started_at,
    pickingEndedAt: row.picking_ended_at,
    createdAt: row.run_created_at,
    runnerId: row.runner_id,
    locationCount: Number(row.location_count ?? 0),
    chocolateBoxes: chocolateBoxesByRun.get(row.run_id) || [],
    runner: buildParticipant(row.runner_id, row.runner_first_name, row.runner_last_name),
  }));
}

function buildParticipant(
  id: string | null,
  firstName: string | null,
  lastName: string | null,
): RunDailyResponse['runner'] {
  if (!id) {
    return null;
  }

  return {
    id,
    firstName,
    lastName,
  };
}

export const runRouter = router;
