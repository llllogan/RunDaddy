import { z } from 'zod';
import { RunStatus, UserRole } from '../../types/enums.js';
import { prisma } from '../../lib/prisma.js';

export const createRunSchema = z.object({
  runnerId: z.string().cuid().optional(),
  status: z.nativeEnum(RunStatus).optional(),
  pickingStartedAt: z.coerce.date().optional(),
  pickingEndedAt: z.coerce.date().optional(),
  scheduledFor: z.coerce.date().optional(),
});

export const updateRunSchema = createRunSchema.partial();

export const createPickEntrySchema = z.object({
  coilItemId: z.string().cuid(),
  count: z.number().int().min(0),
  isPicked: z.boolean().optional(),
  pickedAt: z.coerce.date().optional(),
});

export const updatePickEntrySchema = createPickEntrySchema.partial();

export const createChocolateBoxSchema = z.object({
  machineId: z.string().cuid(),
  number: z.number().int().min(1),
});

export const updateChocolateBoxSchema = z.object({
  machineId: z.string().cuid().optional(),
  number: z.number().int().min(1).optional(),
});

export const runAssignmentSchema = z.object({
  userId: z.string().cuid().optional(),
  role: z.enum(['RUNNER']),
});

export const ensureMembership = async (companyId: string, userId: string | undefined | null) => {
  if (!userId) {
    return null;
  }
  const membership = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId,
        companyId,
      },
    },
    include: {
      user: true,
    },
  });
  return membership;
};

export const ensureRun = async (companyId: string, runId: string) => {
  const run = await prisma.run.findUnique({
    where: { id: runId },
    include: {
      runner: true,
      pickEntries: {
        include: {
          coilItem: {
            include: {
              sku: true,
              coil: {
                include: {
                  machine: {
                    include: {
                      location: true,
                      machineType: true,
                    },
                  },
                },
              },
            },
          },
        },
      },
      chocolateBoxes: {
        include: {
          machine: {
            include: {
              location: true,
              machineType: true,
            },
          },
        },
      },
      locationOrders: {
        include: {
          location: true,
        },
        orderBy: {
          position: 'asc',
        },
      },
      packingSessions: {
        include: {
          user: true,
        },
      },
    },
  });
  if (!run || run.companyId !== companyId) {
    return null;
  }
  return run;
};

export const ensureCoilItem = async (companyId: string, coilItemId: string) => {
  const coilItem = await prisma.coilItem.findUnique({
    where: { id: coilItemId },
    include: {
      coil: {
        include: {
          machine: true,
        },
      },
      sku: true,
    },
  });
  if (!coilItem || coilItem.coil.machine.companyId !== companyId) {
    return null;
  }
  return coilItem;
};

export const ensureMachine = async (companyId: string, machineId: string) => {
  const machine = await prisma.machine.findUnique({ where: { id: machineId } });
  if (!machine || machine.companyId !== companyId) {
    return null;
  }
  return machine;
};
