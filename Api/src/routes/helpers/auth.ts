import type { CookieOptions, Response } from 'express';
import { z } from 'zod';
import { AuthContext, UserRole } from '../../types/enums.js';

export const registerSchema = z.object({
  companyName: z.string().min(2),
  userFirstName: z.string().min(1),
  userLastName: z.string().min(1),
  userEmail: z.string().email(),
  userPassword: z.string().min(8),
  userPhone: z.string().min(7).optional(),
});

export const signupSchema = z.object({
  userFirstName: z.string().min(1),
  userLastName: z.string().min(1),
  userEmail: z.string().email(),
  userPassword: z.string().min(8),
  userPhone: z.string().min(7).optional(),
});

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
  companyId: z.string().cuid().optional(),
  context: z.nativeEnum(AuthContext).default(AuthContext.WEB),
  setAsDefault: z.boolean().optional(),
});

export const switchCompanySchema = z.object({
  companyId: z.string().cuid(),
  context: z.nativeEnum(AuthContext).optional(),
  persist: z.boolean().optional(),
});

export type SessionCompany = { id: string; name: string } | null;
export type SessionUser = {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: UserRole;
  phone?: string | null;
};

export type SessionTokens = {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: Date;
  refreshTokenExpiresAt: Date;
  context: AuthContext;
};

export type MembershipSummary = {
  id: string;
  companyId: string;
  role: UserRole;
  company: { id: string; name: string };
};

const WEB_ALLOWED_ROLES = new Set<UserRole>([UserRole.ADMIN, UserRole.OWNER]);
const ALL_ALLOWED_ROLES = new Set<UserRole>(Object.values(UserRole));

export const getAllowedRolesForContext = (context: AuthContext): ReadonlySet<UserRole> => {
  return context === AuthContext.WEB ? WEB_ALLOWED_ROLES : ALL_ALLOWED_ROLES;
};

export const formatMembershipChoices = (memberships: MembershipSummary[]) =>
  memberships.map((member) => ({
    companyId: member.companyId,
    companyName: member.company.name,
    role: member.role,
  }));

const isProductionEnv = () => process.env.NODE_ENV === 'production';

export const buildAuthCookieOptions = (): CookieOptions & { sameSite: 'strict' } => {
  const isProduction = isProductionEnv();
  return {
    httpOnly: true,
    secure: isProduction,
    sameSite: 'strict',
    path: '/api',
    ...(isProduction ? {} : { domain: 'localhost' }),
  };
};

export const respondWithSession = (
  res: Response,
  data: { company: SessionCompany; user: SessionUser; tokens: SessionTokens },
  status = 200,
  extras?: Record<string, unknown>,
) => {
  const cookieOptions = buildAuthCookieOptions();

  res.cookie('accessToken', data.tokens.accessToken, { ...cookieOptions, expires: data.tokens.accessTokenExpiresAt });
  res.cookie('refreshToken', data.tokens.refreshToken, { ...cookieOptions, expires: data.tokens.refreshTokenExpiresAt });

  const responseData: Record<string, unknown> = {
    company: data.company,
    user: {
      id: data.user.id,
      email: data.user.email,
      firstName: data.user.firstName,
      lastName: data.user.lastName,
      role: data.user.role,
      phone: data.user.phone ?? null,
    },
  };

  if (data.tokens.context === AuthContext.APP) {
    responseData.accessToken = data.tokens.accessToken;
    responseData.refreshToken = data.tokens.refreshToken;
    responseData.accessTokenExpiresAt = data.tokens.accessTokenExpiresAt;
    responseData.refreshTokenExpiresAt = data.tokens.refreshTokenExpiresAt;
    responseData.context = data.tokens.context;
  }

  if (extras && typeof extras === 'object') {
    Object.assign(responseData, extras);
  }

  return res.status(status).json(responseData);
};

export const buildSessionPayload = (
  user: SessionUser,
  company: SessionCompany,
  tokens: SessionTokens,
) => ({
  company,
  user,
  tokens,
});
