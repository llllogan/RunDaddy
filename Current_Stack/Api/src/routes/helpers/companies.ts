import { z } from 'zod';
import type { UserRole } from '../../types/enums.js';

export const updateCompanySchema = z.object({
  name: z.string().min(1),
});

export type CompanyMembershipRecord = {
  company: { id: string; name: string; createdAt: Date; updatedAt: Date };
  role: UserRole;
};

export const toCompanyMembershipResponse = (memberships: CompanyMembershipRecord[]) =>
  memberships.map((membership) => ({
    company: {
      id: membership.company.id,
      name: membership.company.name,
      createdAt: membership.company.createdAt,
      updatedAt: membership.company.updatedAt,
    },
    role: membership.role,
  }));

