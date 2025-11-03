import { z } from 'zod';

export const createLocationSchema = z.object({
  name: z.string().min(1),
  address: z.string().optional(),
});

export const updateLocationSchema = z.object({
  name: z.string().min(1).optional(),
  address: z.string().optional(),
});

