import { UserRole } from '../../types/enums.js';
import { prisma } from '../../lib/prisma.js';

export type MembershipCounts = {
  owners: number;
  admins: number;
  pickers: number;
  total: number;
};

export const buildMembershipCounts = async (companyId: string): Promise<MembershipCounts> => {
  const groups = await prisma.membership.groupBy({
    by: ['role'],
    where: { companyId },
    _count: { _all: true },
  });

  const counts: MembershipCounts = {
    owners: 0,
    admins: 0,
    pickers: 0,
    total: 0,
  };

  groups.forEach((group) => {
    if (group.role === UserRole.OWNER) {
      counts.owners = group._count._all;
    }
    if (group.role === UserRole.ADMIN) {
      counts.admins = group._count._all;
    }
    if (group.role === UserRole.PICKER) {
      counts.pickers = group._count._all;
    }
    counts.total += group._count._all;
  });

  return counts;
};

export const remainingCapacityForRole = (
  tier: { maxOwners: number; maxAdmins: number; maxPickers: number },
  counts: MembershipCounts,
  role: UserRole,
) => {
  let max = Infinity;
  if (role === UserRole.OWNER) {
    max = tier.maxOwners;
    return { remaining: Math.max(max - counts.owners, 0), allowed: counts.owners < max };
  }
  if (role === UserRole.ADMIN) {
    max = tier.maxAdmins;
    return { remaining: Math.max(max - counts.admins, 0), allowed: counts.admins < max };
  }
  if (role === UserRole.PICKER) {
    max = tier.maxPickers;
    return { remaining: Math.max(max - counts.pickers, 0), allowed: counts.pickers < max };
  }

  return { remaining: Infinity, allowed: true };
};

export const getCompanyTierWithCounts = async (companyId: string) => {
  const company = await prisma.company.findUnique({
    where: { id: companyId },
    include: { tier: true },
  });

  if (!company) {
    return null;
  }

  const membershipCounts = await buildMembershipCounts(companyId);
  return { company, tier: company.tier, membershipCounts };
};
