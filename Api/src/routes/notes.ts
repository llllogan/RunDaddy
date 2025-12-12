import { Router } from 'express';
import { z } from 'zod';
import type { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { ensureRun } from './helpers/runs.js';
import { parseTimezoneQueryParam, resolveCompanyTimezone } from './helpers/timezone.js';
import { getTimezoneDayRange, isValidTimezone } from '../lib/timezone.js';
import { isCompanyManager } from './helpers/authorization.js';

const router = Router();

const MAX_NOTES = 100;
const DEFAULT_LIMIT = 50;
const MAX_BODY_LENGTH = 2000;
const MAX_RECENT_DAYS = 30;

const createNoteSchema = z.object({
  body: z.string().trim().min(1).max(MAX_BODY_LENGTH),
  runId: z.string().cuid().optional().nullable(),
  targetType: z.enum(['sku', 'machine', 'location']),
  targetId: z.string().cuid(),
});

const updateNoteSchema = z.object({
  body: z.string().trim().min(1).max(MAX_BODY_LENGTH).optional(),
  targetType: z.enum(['sku', 'machine', 'location']).optional(),
  targetId: z.string().cuid().optional(),
});

const listNotesSchema = z.object({
  runId: z.string().cuid().optional(),
  includePersistentForRun: z
    .preprocess((value) => (value === 'false' ? false : true), z.boolean())
    .optional(),
  recentDays: z
    .preprocess((value) => {
      if (typeof value === 'string' && value.trim().length > 0) {
        const parsed = Number.parseInt(value, 10);
        return Number.isFinite(parsed) ? parsed : undefined;
      }
      if (typeof value === 'number') {
        return value;
      }
      return undefined;
    }, z.number().int().positive())
    .optional(),
  limit: z
    .preprocess((value) => {
      if (typeof value === 'string' && value.trim().length > 0) {
        const parsed = Number.parseInt(value, 10);
        return Number.isFinite(parsed) ? parsed : undefined;
      }
      if (typeof value === 'number') {
        return value;
      }
      return undefined;
    }, z.number().int().min(1).max(MAX_NOTES))
    .optional(),
  timezone: z.string().trim().optional(),
});

type RunNoteContext = {
  skuIds: Set<string>;
  machineIds: Set<string>;
  locationIds: Set<string>;
};

type NoteWithRelations = Prisma.NoteGetPayload<{
  include: {
    sku: true;
    machine: {
      include: {
        location: true;
        machineType: true;
      };
    };
    location: true;
  };
}>;

router.use(authenticate);

router.get('/', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to modify notes' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to access notes' });
  }

  const parsed = listNotesSchema.safeParse(req.query);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid query parameters', details: parsed.error.flatten() });
  }

  const { runId, includePersistentForRun = true, recentDays, limit, timezone } = parsed.data;
  const companyId = req.auth.companyId;
  const filters: Prisma.NoteWhereInput[] = [{ companyId }];

  // Apply date window if requested (e.g., today + yesterday)
  if (recentDays) {
    const clampedDays = Math.min(recentDays, MAX_RECENT_DAYS);
    const timezoneOverride = parseTimezoneQueryParam(timezone);
    if (timezoneOverride && !isValidTimezone(timezoneOverride)) {
      return res.status(400).json({
        error: 'Invalid timezone supplied. Please use an IANA timezone like "America/Chicago".',
      });
    }
    const timeZone = await resolveCompanyTimezone(companyId, timezoneOverride);
    const startOffset = -(clampedDays - 1);
    const startRange = getTimezoneDayRange({ timeZone, dayOffset: startOffset }).start;
    const endRange = getTimezoneDayRange({ timeZone, dayOffset: 0 }).end;
    filters.push({
      createdAt: {
        gte: startRange,
        lt: endRange,
      },
    });
  }

  if (runId) {
    const run = await ensureRun(companyId, runId);
    if (!run) {
      return res.status(404).json({ error: 'Run not found' });
    }

    const context = buildRunContext(run);
    const runFilters: Prisma.NoteWhereInput[] = [{ runId }];

    if (includePersistentForRun) {
      const persistent: Prisma.NoteWhereInput[] = [];
      if (context.skuIds.size > 0) {
        persistent.push({
          runId: null,
          skuId: { in: Array.from(context.skuIds) },
        });
      }
      if (context.machineIds.size > 0) {
        persistent.push({
          runId: null,
          machineId: { in: Array.from(context.machineIds) },
        });
      }
      if (context.locationIds.size > 0) {
        persistent.push({
          runId: null,
          locationId: { in: Array.from(context.locationIds) },
        });
      }

      if (persistent.length > 0) {
        runFilters.push({ OR: persistent });
      }
    }

    filters.push({ OR: runFilters });
  }

  const where = filters.length === 1 ? filters[0] : { AND: filters };
  const take = Math.min(limit ?? DEFAULT_LIMIT, MAX_NOTES);

  const [total, notes] = await prisma.$transaction([
    prisma.note.count({ where }),
    prisma.note.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take,
      include: {
        sku: true,
        machine: {
          include: {
            location: true,
            machineType: true,
          },
        },
        location: true,
      },
    }),
  ]);

  return res.json({
    total,
    notes: notes.map(serializeNote),
  });
});

router.post('/', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to create notes' });
  }

  const parsed = createNoteSchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const { body, runId, targetId, targetType } = parsed.data;
  const normalizedBody = body.trim();
  const companyId = req.auth.companyId;
  let runContext: RunNoteContext | null = null;

  if (runId) {
    const run = await ensureRun(companyId, runId);
    if (!run) {
      return res.status(404).json({ error: 'Run not found' });
    }
    runContext = buildRunContext(run);
  }

  const target = await ensureTarget(companyId, targetType, targetId);
  if (!target) {
    return res.status(404).json({ error: 'Target not found for this company' });
  }

  if (runContext && !isTargetInRun(targetType, targetId, runContext)) {
    return res.status(400).json({
      error: 'Selected tag is not part of this run',
    });
  }

  const created = await prisma.note.create({
    data: {
      body: normalizedBody,
      companyId,
      runId: runId ?? null,
      createdBy: req.auth.userId ?? null,
      skuId: targetType === 'sku' ? targetId : null,
      machineId: targetType === 'machine' ? targetId : null,
      locationId: targetType === 'location' ? targetId : null,
    },
    include: {
      sku: true,
      machine: {
        include: {
          location: true,
          machineType: true,
        },
      },
      location: true,
    },
  });

  return res.status(201).json(serializeNote(created));
});

router.patch('/:noteId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to update notes' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to modify notes' });
  }

  const noteId = req.params.noteId?.trim();
  if (!noteId) {
    return res.status(400).json({ error: 'Note ID is required' });
  }

  const parsed = updateNoteSchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid payload', details: parsed.error.flatten() });
  }

  const existing = await prisma.note.findUnique({
    where: { id: noteId },
    include: {
      sku: true,
      machine: { include: { location: true, machineType: true } },
      location: true,
    },
  });

  if (!existing || existing.companyId !== req.auth.companyId) {
    return res.status(404).json({ error: 'Note not found' });
  }

  if (existing.runId) {
    const run = await ensureRun(req.auth.companyId, existing.runId);
    if (!run) {
      return res.status(404).json({ error: 'Run not found' });
    }
    if (parsed.data.targetType && parsed.data.targetId) {
      const runContext = buildRunContext(run);
      if (!isTargetInRun(parsed.data.targetType, parsed.data.targetId, runContext)) {
        return res.status(400).json({ error: 'Selected tag is not part of this run' });
      }
    }
  }

  let targetFieldUpdates: Prisma.NoteUpdateInput = {};
  if (parsed.data.targetType && parsed.data.targetId) {
    const target = await ensureTarget(req.auth.companyId, parsed.data.targetType, parsed.data.targetId);
    if (!target) {
      return res.status(404).json({ error: 'Target not found for this company' });
    }

    targetFieldUpdates = {
      skuId: parsed.data.targetType === 'sku' ? parsed.data.targetId : null,
      machineId: parsed.data.targetType === 'machine' ? parsed.data.targetId : null,
      locationId: parsed.data.targetType === 'location' ? parsed.data.targetId : null,
    };
  }

  const updated = await prisma.note.update({
    where: { id: noteId },
    data: {
      body: parsed.data.body?.trim() ?? existing.body,
      ...targetFieldUpdates,
    },
    include: {
      sku: true,
      machine: { include: { location: true, machineType: true } },
      location: true,
    },
  });

  return res.json(serializeNote(updated));
});

router.delete('/:noteId', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(403).json({ error: 'Company membership required to delete notes' });
  }

  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to modify notes' });
  }

  const noteId = req.params.noteId?.trim();
  if (!noteId) {
    return res.status(400).json({ error: 'Note ID is required' });
  }

  const existing = await prisma.note.findUnique({
    where: { id: noteId },
    select: { id: true, companyId: true },
  });

  if (!existing || existing.companyId !== req.auth.companyId) {
    return res.status(404).json({ error: 'Note not found' });
  }

  await prisma.note.delete({ where: { id: noteId } });
  return res.status(204).send();
});

export const notesRouter = router;

async function ensureTarget(companyId: string, type: 'sku' | 'machine' | 'location', targetId: string) {
  if (type === 'sku') {
    const sku = await prisma.sKU.findUnique({ where: { id: targetId } });
    if (!sku || sku.companyId !== companyId) {
      return null;
    }
    return sku;
  }

  if (type === 'machine') {
    const machine = await prisma.machine.findUnique({
      where: { id: targetId },
      include: { location: true },
    });
    if (!machine || machine.companyId !== companyId) {
      return null;
    }
    return machine;
  }

  const location = await prisma.location.findUnique({ where: { id: targetId } });
  if (!location || location.companyId !== companyId) {
    return null;
  }
  return location;
}

function buildRunContext(run: NonNullable<Awaited<ReturnType<typeof ensureRun>>>): RunNoteContext {
  const skuIds = new Set<string>();
  const machineIds = new Set<string>();
  const locationIds = new Set<string>();

  run.pickEntries.forEach((entry) => {
    if (entry.coilItem.skuId) {
      skuIds.add(entry.coilItem.skuId);
    }
    if (entry.coilItem.coil.machineId) {
      machineIds.add(entry.coilItem.coil.machineId);
    }
    const locationId = entry.coilItem.coil.machine.locationId;
    if (locationId) {
      locationIds.add(locationId);
    }
  });

  run.locationOrders.forEach((order) => {
    if (order.locationId) {
      locationIds.add(order.locationId);
    }
  });

  return { skuIds, machineIds, locationIds };
}

function isTargetInRun(
  type: 'sku' | 'machine' | 'location',
  targetId: string,
  context: RunNoteContext,
): boolean {
  switch (type) {
    case 'sku':
      return context.skuIds.has(targetId);
    case 'machine':
      return context.machineIds.has(targetId);
    case 'location':
      return context.locationIds.has(targetId);
    default:
      return false;
  }
}

function serializeNote(note: NoteWithRelations) {
  const target = resolveTarget(note);

  return {
    id: note.id,
    body: note.body,
    runId: note.runId,
    createdAt: note.createdAt,
    scope: note.runId ? 'run' as const : 'persistent' as const,
    target,
  };
}

function resolveTarget(note: NoteWithRelations) {
  if (note.sku) {
    return {
      type: 'sku' as const,
      id: note.sku.id,
      label: note.sku.code,
      subtitle: buildSkuSubtitle(note.sku.name, note.sku.type, note.sku.category),
    };
  }

  if (note.machine) {
    const locationLabel =
      note.machine.location?.name?.trim() || note.machine.location?.address?.trim() || null;
    const description = note.machine.description?.trim();

    return {
      type: 'machine' as const,
      id: note.machine.id,
      label: note.machine.code,
      subtitle: description && description.length > 0 ? description : null,
    };
  }

  const locationLabel = note.location?.name?.trim() || 'Location';
  const locationSubtitle = note.location?.address?.trim() || null;

  return {
    type: 'location' as const,
    id: note.location?.id ?? '',
    label: locationLabel,
    subtitle: locationSubtitle,
  };
}

function buildSkuSubtitle(name: string | null | undefined, type: string | null | undefined, category: string | null | undefined) {
  const parts: string[] = [];
  if (name && name.trim().length > 0) {
    parts.push(name.trim());
  }
  if (type && type.trim().length > 0) {
    parts.push(type.trim());
  }
  if (category && category.trim().length > 0) {
    parts.push(category.trim());
  }
  return parts.length ? parts.join(' • ') : null;
}
