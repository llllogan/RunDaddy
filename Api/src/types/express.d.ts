import type { UserRole } from '@prisma/client';

export interface AuthenticatedUser {
  userId: string;
  companyId: string;
  email: string;
  role: UserRole;
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
