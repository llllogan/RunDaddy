import { z } from 'zod';
import { UserRole } from '../../types/enums.js';

export const createUserSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  phone: z.string().min(7).optional(),
  role: z.nativeEnum(UserRole).default(UserRole.PICKER),
});

export const updateUserSchema = z.object({
  firstName: z.string().min(1).optional(),
  lastName: z.string().min(1).optional(),
  phone: z.string().optional(),
  password: z.string().min(8).optional(),
  role: z.nativeEnum(UserRole).optional(),
});

export const userLookupSchema = z.object({
  userIds: z.array(z.string().cuid()).max(100),
});

