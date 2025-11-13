import { prisma } from './prisma.js';
import { UserRole } from '../types/enums.js';
import { PLATFORM_ADMIN_COMPANY_ID } from '../config/platform-admin.js';

export const isPlatformAdminCompany = (companyId: string | null | undefined): boolean => {
  return Boolean(companyId && companyId === PLATFORM_ADMIN_COMPANY_ID);
};

export const userHasPlatformAdminAccess = async (userId: string): Promise<boolean> => {
  if (!userId) {
    return false;
  }

  const membership = await prisma.membership.findFirst({
    where: {
      userId,
      companyId: PLATFORM_ADMIN_COMPANY_ID,
      role: UserRole.GOD,
    },
    select: { id: true },
  });

  return Boolean(membership);
};
