import type { AuthContext, UserRole, AccountRole } from './enums.js';

export interface AuthenticatedUser {
  userId: string;
  companyId: string | null;
  email: string;
  role: UserRole;
  context: AuthContext;
  lighthouse?: boolean;
  accountRole?: AccountRole | null;
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
