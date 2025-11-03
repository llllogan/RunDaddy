import { z } from 'zod';

export const createSkuSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  type: z.string().min(1),
  isCheeseAndCrackers: z.boolean().optional(),
});

export const updateSkuSchema = z.object({
  code: z.string().min(1).optional(),
  name: z.string().min(1).optional(),
  type: z.string().min(1).optional(),
  isCheeseAndCrackers: z.boolean().optional(),
});

