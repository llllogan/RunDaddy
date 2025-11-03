import { z } from 'zod';
import { prisma } from '../../lib/prisma.js';

export const createMachineSchema = z.object({
  code: z.string().min(1),
  description: z.string().optional(),
  machineTypeId: z.string().cuid(),
  locationId: z.string().cuid().optional(),
});

export const updateMachineSchema = z.object({
  code: z.string().min(1).optional(),
  description: z.string().optional(),
  machineTypeId: z.string().cuid().optional(),
  locationId: z.string().cuid().optional(),
});

export const createCoilSchema = z.object({
  code: z.string().min(1),
});

export const updateCoilSchema = z.object({
  code: z.string().min(1).optional(),
});

export const createCoilItemSchema = z.object({
  skuId: z.string().cuid(),
  par: z.number().int().min(0),
});

export const updateCoilItemSchema = z.object({
  skuId: z.string().cuid().optional(),
  par: z.number().int().min(0).optional(),
});

export const ensureMachine = async (companyId: string, machineId: string) => {
  const machine = await prisma.machine.findUnique({
    where: { id: machineId },
    include: {
      machineType: true,
      location: true,
    },
  });
  if (!machine || machine.companyId !== companyId) {
    return null;
  }
  return machine;
};

export const ensureCoil = async (machineId: string, coilId: string) => {
  const coil = await prisma.coil.findUnique({
    where: { id: coilId },
    include: {
      coilItems: {
        include: { sku: true },
      },
    },
  });
  if (!coil || coil.machineId !== machineId) {
    return null;
  }
  return coil;
};

export const ensureCoilItem = async (coilId: string, coilItemId: string) => {
  const coilItem = await prisma.coilItem.findUnique({
    where: { id: coilItemId },
    include: { sku: true, coil: true },
  });
  if (!coilItem || coilItem.coilId !== coilId) {
    return null;
  }
  return coilItem;
};

