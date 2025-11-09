import { Router } from 'express';
import { z } from 'zod';
import { Prisma } from '@prisma/client';
import type { RunStatus as PrismaRunStatus, RunItemStatus as PrismaRunItemStatus } from '@prisma/client';
import { RunItemStatus, RunStatus as AppRunStatus, isRunStatus } from '../types/enums.js';
import type { RunStatus as RunStatusValue, RunItemStatus as RunItemStatusValue } from '../types/enums.js';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
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

interface AudioCommand {
  id: string;
  audioCommand: string;
  pickEntryIds: string[];
  type: 'location' | 'machine' | 'item';
  locationName?: string;
  machineName?: string;
  skuName?: string;
  skuCode?: string;
  count: number;
  coilCode?: string;
  coilCodes?: string[]; // Array of all coil codes for UI display
  order: number;
}

const router = Router();

const UNASSIGNED_LOCATION_KEY = '__unassigned__';

const updateLocationOrderSchema = z.object({
  locations: z
    .array(
      z.object({
        locationId: z.string().trim().min(1).optional().nullable(),
      }),
    )
    .min(1, 'At least one location is required to save an order.'),
});

router.use(authenticate);

// Lists runs for the current company, optionally filtered by status.
router.get('/', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Return empty array for users without company
  if (!req.auth.companyId) {
    return res.json([]);
  }

  const { status } = req.query;
  const where: Prisma.RunWhereInput = { companyId: req.auth.companyId };
  if (isRunStatus(status)) {
    where.status = { equals: status as unknown as PrismaRunStatus };
  }

  const runs = await prisma.run.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    include: {
      picker: true,
      runner: true,
    },
  });

  return res.json(runs);
});

// Get all runs scheduled for today
// Include the number of locations
router.get('/today', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Return empty array for users without company
  if (!req.auth.companyId) {
    return res.json([]);
  }

  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);

  const runs = await fetchScheduledRuns(req.auth.companyId, startOfToday);

  return res.json(runs);
});

// Get all runs scheduled for tomorrow
router.get('/tomorrow', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Return empty array for users without company
  if (!req.auth.companyId) {
    return res.json([]);
  }

  const startOfTomorrow = new Date();
  startOfTomorrow.setDate(startOfTomorrow.getDate() + 1);
  startOfTomorrow.setHours(0, 0, 0, 0);

  const runs = await fetchScheduledRuns(req.auth.companyId, startOfTomorrow);

  return res.json(runs);
});

// Get audio commands for a run's packing session
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

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const locationOrderMap = new Map<string, number>();
  run.locationOrders.forEach((order) => {
    const key = order.locationId ?? UNASSIGNED_LOCATION_KEY;
    locationOrderMap.set(key, order.position);
  });

  // Get pick entries that need to be packed, ordered by location, then machine, then coil (largest to smallest)
  const pickEntries = await prisma.pickEntry.findMany({
    where: {
      runId: runId,
      status: 'PENDING',
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

  sortedLocationGroups.forEach(locationGroup => {
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
        locationName: location.name || 'Unknown',
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
          audioCommand: `Machine ${machine.code || machine.description || 'Unknown'}`,
          pickEntryIds: [],
          type: 'machine',
          machineName: machine.code || machine.description || 'Unknown',
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
          // Calculate total count for this SKU group
          const countPointer = sku.countNeededPointer || 'total';
          let totalCount = 0;
          
          entries.forEach(entry => {
            let count = entry.count; // fallback to stored count
            
            switch (countPointer.toLowerCase()) {
              case 'current':
                count = entry.current ?? entry.count;
                break;
              case 'par':
                count = entry.par ?? entry.count;
                break;
              case 'need':
                count = entry.need ?? entry.count;
                break;
              case 'forecast':
                count = entry.forecast ?? entry.count;
                break;
              case 'total':
              default:
                count = entry.total ?? entry.count;
                break;
            }
            
            totalCount += count;
          });
          
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
            machineName: machine?.code || machine?.description || 'Unknown',
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

// Get all runs for the company
router.get('/all', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Return empty array for users without company
  if (!req.auth.companyId) {
    return res.json([]);
  }

  const { limit = 50, offset = 0 } = req.query;
  const limitNum = Math.min(Number(limit) || 50, 200); // Cap at 200 runs
  const offsetNum = Number(offset) || 0;

  // Use the same view as today/tomorrow endpoints for consistency
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
        picker_id,
        picker_first_name,
        picker_last_name,
        runner_id,
        runner_first_name,
        runner_last_name,
        location_count
      FROM v_run_daily_locations
      WHERE company_id = ${req.auth.companyId}
      ORDER BY scheduled_for DESC, run_created_at DESC
      LIMIT ${limitNum}
      OFFSET ${offsetNum}
    `
  );

  // Fetch chocolate boxes for all runs
  const runIds = rows.map(row => row.run_id);
  const chocolateBoxes = runIds.length > 0 ? await prisma.chocolateBox.findMany({
    where: {
      runId: { in: runIds }
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
      number: 'asc'
    }
  }) : [];

  // Group chocolate boxes by run
  const chocolateBoxesByRun = new Map<string, Array<{id: string, number: number, machine: any}>>();
  chocolateBoxes.forEach(box => {
    if (!chocolateBoxesByRun.has(box.runId)) {
      chocolateBoxesByRun.set(box.runId, []);
    }
    chocolateBoxesByRun.get(box.runId)!.push({
      id: box.id,
      number: box.number,
      machine: box.machine
    });
  });

  return res.json(rows.map((row) => ({
    id: row.run_id,
    status: row.run_status,
    scheduledFor: row.scheduled_for,
    pickingStartedAt: row.picking_started_at,
    pickingEndedAt: row.picking_ended_at,
    createdAt: row.run_created_at,
    locationCount: Number(row.location_count ?? 0),
    chocolateBoxes: chocolateBoxesByRun.get(row.run_id) || [],
    picker: row.picker_id ? {
      id: row.picker_id,
      firstName: row.picker_first_name,
      lastName: row.picker_last_name,
    } : null,
    runner: row.runner_id ? {
      id: row.runner_id,
      firstName: row.runner_first_name,
      lastName: row.runner_last_name,
    } : null,
  })));
});

// Get runs scheduled for tomorrow with a status of READY
router.get('/tomorrow/ready', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.json([]);
  }

  const startOfTomorrow = new Date();
  startOfTomorrow.setDate(startOfTomorrow.getDate() + 1);
  startOfTomorrow.setHours(0, 0, 0, 0);
  const endOfTomorrow = new Date();
  endOfTomorrow.setDate(endOfTomorrow.getDate() + 1);
  endOfTomorrow.setHours(23, 59, 59, 999);

  const runs = await prisma.run.findMany({
    where: {
      companyId: req.auth.companyId,
      scheduledFor: {
        gte: startOfTomorrow,
        lte: endOfTomorrow,
      },
      status: AppRunStatus.READY,
    },
    orderBy: { scheduledFor: 'asc' },
    include: {
      picker: true,
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

router.put('/:runId/location-order', setLogConfig({ level: 'full' }), async (req, res) => {
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

  const normalizedLocations = parsed.data.locations.reduce<Array<string | null>>((acc, entry) => {
    const key = entry.locationId ?? UNASSIGNED_LOCATION_KEY;
    if (acc.find((candidate) => (candidate ?? UNASSIGNED_LOCATION_KEY) === key)) {
      return acc;
    }
    acc.push(entry.locationId ?? null);
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

// Assigns or unassigns a picker or runner to a run.
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
  console.log('Run found:', !!run, run?.companyId);
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
      const isPickerTaken = parsed.data.role === 'PICKER' && run.pickerId != null && run.pickerId !== req.auth.userId;
      const isRunnerTaken = parsed.data.role === 'RUNNER' && run.runnerId != null && run.runnerId !== req.auth.userId;
      if (isPickerTaken || isRunnerTaken) {
        return res.status(409).json({ error: 'Role is already assigned to another user' });
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
  const updateData = parsed.data.role === 'PICKER'
    ? { pickerId: userId }
    : { runnerId: userId };

  const updatedRun = await prisma.run.update({
    where: { id: run.id },
    data: updateData,
    include: {
      picker: true,
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
      picker: true,
      runner: true,
    },
  });

  return res.status(200).json({
    id: updatedRun.id,
    status: updatedRun.status,
  });
});

// Updates a pick item status (PICKED/PENDING)
router.patch('/:runId/picks/:pickId', async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to update picks' });
  }

  const { runId, pickId } = req.params;
  if (!runId || !pickId) {
    return res.status(400).json({ error: 'Run ID and Pick ID are required' });
  }

  const { status } = req.body;
  if (!status || !['PICKED', 'PENDING', 'SKIPPED'].includes(status)) {
    return res.status(400).json({ error: 'Status must be PICKED, PENDING, or SKIPPED' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  // Find the pick entry
  const pickEntry = await prisma.pickEntry.findFirst({
    where: {
      id: pickId,
      runId: runId
    }
  });

  if (!pickEntry) {
    return res.status(404).json({ error: 'Pick entry not found' });
  }

  const updateData: Prisma.PickEntryUpdateInput = { status };
  if (status === 'PICKED' && !pickEntry.pickedAt) {
    updateData.pickedAt = new Date();
  } else if (status === 'PENDING' || status === 'SKIPPED') {
    updateData.pickedAt = null;
  }

  const updatedPickEntry = await prisma.pickEntry.update({
    where: { id: pickEntry.id },
    data: updateData
  });

  // If this is the first pick entry being packed, update pickingStartedAt and run status
  if (status === 'PICKED' && !run.pickingStartedAt) {
    await prisma.run.update({
      where: { id: run.id },
      data: { 
        pickingStartedAt: new Date(),
        ...(run.status === 'CREATED' && { status: 'PICKING' })
      }
    });
  }

  return res.json({
    id: updatedPickEntry.id,
    status: updatedPickEntry.status,
    pickedAt: updatedPickEntry.pickedAt
  });
});

// Bulk update pick entries status for packing session
router.patch('/:runId/picks/bulk', async (req, res) => {
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

  const { pickIds, status } = req.body;
  if (!Array.isArray(pickIds) || pickIds.length === 0) {
    return res.status(400).json({ error: 'Pick IDs array is required' });
  }

  if (!status || !['PICKED', 'PENDING', 'SKIPPED'].includes(status)) {
    return res.status(400).json({ error: 'Status must be PICKED, PENDING, or SKIPPED' });
  }

  const run = await ensureRun(req.auth.companyId, runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  // Update all specified pick entries
  const updateData: Prisma.PickEntryUpdateInput = { status };
  if (status === 'PICKED') {
    updateData.pickedAt = new Date();
  } else {
    updateData.pickedAt = null;
  }

  const updatedPickEntries = await prisma.pickEntry.updateMany({
    where: {
      id: { in: pickIds },
      runId: runId
    },
    data: updateData
  });

  // If this is the first pick entry being packed, update pickingStartedAt and run status
  if (status === 'PICKED' && !run.pickingStartedAt) {
    await prisma.run.update({
      where: { id: run.id },
      data: { 
        pickingStartedAt: new Date(),
        ...(run.status === 'CREATED' && { status: 'PICKING' })
      }
    });
  }

  return res.json({
    updatedCount: updatedPickEntries.count,
    status: status
  });
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
  status: RunItemStatusValue;
  pickedAt: Date | null;
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
    isCheeseAndCrackers: boolean;
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
  picker: null | {
    id: string;
    firstName: string | null;
    lastName: string | null;
  };
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
    status: RunItemStatusValue;
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
  chocolateBoxes: Array<{
    id: string;
    number: number;
    machine: MachinePayload | null;
  }>;
  locationOrders: LocationOrderPayload[];
};

function buildRunDetailPayload(run: RunDetailSource): RunDetailPayload {
  const machinesById = new Map<string, MachinePayload>();
  const locationsById = new Map<string, LocationPayload>();

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

    // Determine count based on SKU's countNeededPointer
    const countPointer = entry.coilItem.sku?.countNeededPointer || 'total';
    let calculatedCount = entry.count; // fallback to stored count

    switch (countPointer.toLowerCase()) {
      case 'current':
        calculatedCount = entry.current ?? entry.count;
        break;
      case 'par':
        calculatedCount = entry.par ?? entry.count;
        break;
      case 'need':
        calculatedCount = entry.need ?? entry.count;
        break;
      case 'forecast':
        calculatedCount = entry.forecast ?? entry.count;
        break;
      case 'total':
      default:
        calculatedCount = entry.total ?? entry.count;
        break;
    }

    return {
      id: entry.id,
      count: calculatedCount,
      current: entry.current,
      par: entry.par,
      need: entry.need,
      forecast: entry.forecast,
      total: entry.total,
      status: entry.status as RunItemStatusValue,
      pickedAt: entry.pickedAt,
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
            isCheeseAndCrackers: entry.coilItem.sku.isCheeseAndCrackers,
            countNeededPointer: (entry.coilItem.sku as any).countNeededPointer,
          }
        : null,
      machine: serializedMachine,
      location: serializedLocation,
    };
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
    picker: run.picker
      ? {
          id: run.picker.id,
          firstName: run.picker.firstName,
          lastName: run.picker.lastName,
        }
      : null,
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
      // Determine count based on SKU's countNeededPointer
      const countPointer = entry.coilItem.sku?.countNeededPointer || 'total';
      let calculatedCount = entry.count; // fallback to stored count

      switch (countPointer.toLowerCase()) {
        case 'current':
          calculatedCount = entry.current ?? entry.count;
          break;
        case 'par':
          calculatedCount = entry.par ?? entry.count;
          break;
        case 'need':
          calculatedCount = entry.need ?? entry.count;
          break;
        case 'forecast':
          calculatedCount = entry.forecast ?? entry.count;
          break;
        case 'total':
        default:
          calculatedCount = entry.total ?? entry.count;
          break;
      }

      return {
        id: entry.id,
        count: calculatedCount,
        current: entry.current,
        par: entry.par,
        need: entry.need,
        forecast: entry.forecast,
        total: entry.total,
        status: entry.status as RunItemStatusValue,
        pickedAt: entry.pickedAt,
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
                isCheeseAndCrackers: entry.coilItem.sku.isCheeseAndCrackers,
              }
            : null,
        },
      };
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
  picker_id: string | null;
  picker_first_name: string | null;
  picker_last_name: string | null;
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
  pickerId: string | null;
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
  picker: null | {
    id: string;
    firstName: string | null;
    lastName: string | null;
  };
  runner: null | {
    id: string;
    firstName: string | null;
    lastName: string | null;
  };
};

async function fetchScheduledRuns(companyId: string, scheduledDate: Date): Promise<RunDailyResponse[]> {
  const formattedDate = formatDateYmd(scheduledDate);

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
        picker_id,
        picker_first_name,
        picker_last_name,
        runner_id,
        runner_first_name,
        runner_last_name,
        location_count
      FROM v_run_daily_locations
      WHERE company_id = ${companyId}
        AND scheduled_date = ${formattedDate}
      ORDER BY scheduled_for ASC, run_created_at ASC
    `,
  );

  // Fetch chocolate boxes for all runs
  const runIds = rows.map(row => row.run_id);
  const chocolateBoxes = runIds.length > 0 ? await prisma.chocolateBox.findMany({
    where: {
      runId: { in: runIds }
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
      number: 'asc'
    }
  }) : [];

  // Group chocolate boxes by run
  const chocolateBoxesByRun = new Map<string, Array<{id: string, number: number, machine: any}>>();
  chocolateBoxes.forEach(box => {
    if (!chocolateBoxesByRun.has(box.runId)) {
      chocolateBoxesByRun.set(box.runId, []);
    }
    chocolateBoxesByRun.get(box.runId)!.push({
      id: box.id,
      number: box.number,
      machine: box.machine
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
    pickerId: row.picker_id,
    runnerId: row.runner_id,
    locationCount: Number(row.location_count ?? 0),
    chocolateBoxes: chocolateBoxesByRun.get(row.run_id) || [],
    picker: buildParticipant(row.picker_id, row.picker_first_name, row.picker_last_name),
    runner: buildParticipant(row.runner_id, row.runner_first_name, row.runner_last_name),
  }));
}

function buildParticipant(
  id: string | null,
  firstName: string | null,
  lastName: string | null,
): RunDailyResponse['picker'] {
  if (!id) {
    return null;
  }

  return {
    id,
    firstName,
    lastName,
  };
}

function formatDateYmd(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export const runRouter = router;
