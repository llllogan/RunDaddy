import { z } from 'zod';
import { UserRole } from '../../types/enums.js';

export const createCompanySchema = z.object({
  name: z.string().min(1, 'Company name is required'),
});

export const createUserSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  phone: z.string().min(7).optional(),
  role: z.nativeEnum(UserRole).default(UserRole.PICKER),
  companyId: z.string().cuid().optional(),
  membershipRole: z.nativeEnum(UserRole).optional(),
  setAsDefaultMembership: z.boolean().optional(),
});

export const createMembershipSchema = z.object({
  userId: z.string().cuid(),
  companyId: z.string().cuid(),
  role: z.nativeEnum(UserRole).default(UserRole.PICKER),
  setAsDefault: z.boolean().optional(),
});

