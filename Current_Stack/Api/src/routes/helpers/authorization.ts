import { UserRole } from '../../types/enums.js';

const COMPANY_MANAGER_ROLE_SET = new Set<UserRole>([UserRole.ADMIN, UserRole.OWNER]);

export const COMPANY_MANAGER_ROLES: ReadonlySet<UserRole> = COMPANY_MANAGER_ROLE_SET;

export const isCompanyManager = (role: UserRole): boolean => COMPANY_MANAGER_ROLE_SET.has(role);

