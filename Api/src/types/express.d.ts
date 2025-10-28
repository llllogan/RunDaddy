import type { AdminRole } from '@prisma/client';

export interface AuthenticatedUser {
  adminId: string;
  companyId: string;
  email: string;
  role: AdminRole;
}

declare global {
  namespace Express {
    interface Request {
      auth?: AuthenticatedUser;
      refreshTokenId?: string;
    }
  }
}

export {};
