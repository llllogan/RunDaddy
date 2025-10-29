import type { UserRole } from './enums.js';

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
