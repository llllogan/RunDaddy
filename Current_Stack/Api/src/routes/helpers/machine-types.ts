import { z } from 'zod';

export const createMachineTypeSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
});

export const updateMachineTypeSchema = z.object({
  name: z.string().min(1).optional(),
  description: z.string().optional(),
});

