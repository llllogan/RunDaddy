import type { AuthContext, UserRole } from './enums.js';

export interface AuthenticatedUser {
  userId: string;
  companyId: string;
  email: string;
  role: UserRole;
  context: AuthContext;
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
