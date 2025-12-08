import jwt from 'jsonwebtoken';
import { randomUUID } from 'node:crypto';
import { AuthContext, type UserRole } from '../types/enums.js';

const { sign, verify } = jwt;

type BaseClaims = {
  sub: string;
  companyId: string | null;
  email: string;
  role: UserRole;
  context: AuthContext;
  lighthouse?: boolean;
};

export type AccessTokenClaims = BaseClaims & { exp?: number; iat?: number };

export type RefreshTokenClaims = AccessTokenClaims & { tokenId: string };

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: Date;
  refreshTokenExpiresAt: Date;
  refreshTokenId: string;
  context: AuthContext;
}

export interface TokenPayloadInput {
  userId: string;
  companyId: string | null;
  email: string;
  role: UserRole;
  context: AuthContext;
  lighthouse?: boolean;
}

const DEFAULT_ACCESS_DURATION = '15m';
const DEFAULT_REFRESH_DURATION = '7d';
const APP_ACCESS_DURATION = '7d';
const APP_REFRESH_DURATION = '180d';

const DURATION_REGEX = /^(\d+)(ms|s|m|h|d)$/i;
const DURATION_MULTIPLIERS: Record<string, number> = {
  ms: 1,
  s: 1000,
  m: 60 * 1000,
  h: 60 * 60 * 1000,
  d: 24 * 60 * 60 * 1000,
};

const requireEnv = (key: string): string => {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable "${key}"`);
  }
  return value;
};

const getDurationMs = (value: string | undefined, fallback: string): number => {
  const source = value?.trim() ?? fallback;
  const numeric = Number(source);
  if (!Number.isNaN(numeric) && numeric > 0) {
    return numeric;
  }

  const match = source.match(DURATION_REGEX);
  if (!match) {
    throw new Error(`Invalid duration value "${source}". Expected number or [number][ms|s|m|h|d].`);
  }

  const [, amountRaw, unitRaw] = match;
  if (!amountRaw || !unitRaw) {
    throw new Error(`Invalid duration format "${source}"`);
  }
  const amount = Number(amountRaw);
  const unit = unitRaw.toLowerCase() as keyof typeof DURATION_MULTIPLIERS;
  const multiplier = DURATION_MULTIPLIERS[unit];
  if (multiplier === undefined) {
    throw new Error(`Unsupported duration unit "${unit}"`);
  }
  return amount * multiplier;
};

const resolveContextDurations = (context: AuthContext): { access: number; refresh: number } => {
  const base = context === AuthContext.APP
    ? { access: APP_ACCESS_DURATION, refresh: APP_REFRESH_DURATION }
    : { access: DEFAULT_ACCESS_DURATION, refresh: DEFAULT_REFRESH_DURATION };

  const accessKey = `JWT_${context}_ACCESS_EXPIRES_IN`;
  const refreshKey = `JWT_${context}_REFRESH_EXPIRES_IN`;
  const legacyAccess = context === AuthContext.WEB ? process.env.JWT_ACCESS_EXPIRES_IN : undefined;
  const legacyRefresh = context === AuthContext.WEB ? process.env.JWT_REFRESH_EXPIRES_IN : undefined;

  const accessExpiresMs = getDurationMs(process.env[accessKey] ?? legacyAccess, base.access);
  const refreshExpiresMs = getDurationMs(process.env[refreshKey] ?? legacyRefresh, base.refresh);

  return { access: accessExpiresMs, refresh: refreshExpiresMs };
};

export const createTokenPair = (input: TokenPayloadInput): TokenPair => {
  const accessSecret = requireEnv('JWT_ACCESS_SECRET');
  const refreshSecret = requireEnv('JWT_REFRESH_SECRET');
  const { access: accessExpiresMs, refresh: refreshExpiresMs } = resolveContextDurations(input.context);
  const accessExpiresSeconds = Math.max(1, Math.floor(accessExpiresMs / 1000));
  const refreshExpiresSeconds = Math.max(1, Math.floor(refreshExpiresMs / 1000));
  const tokenId = randomUUID();
  const now = Date.now();
  const claims: BaseClaims = {
    sub: input.userId,
    companyId: input.companyId,
    email: input.email,
    role: input.role,
    context: input.context,
    ...(input.lighthouse ? { lighthouse: true } : {}),
  };

  const accessToken = sign(claims, accessSecret, {
    expiresIn: accessExpiresSeconds,
  });

  const refreshToken = sign({ ...claims, tokenId }, refreshSecret, {
    expiresIn: refreshExpiresSeconds,
  });

  return {
    accessToken,
    refreshToken,
    accessTokenExpiresAt: new Date(now + accessExpiresMs),
    refreshTokenExpiresAt: new Date(now + refreshExpiresMs),
    refreshTokenId: tokenId,
    context: input.context,
  };
};

export const verifyAccessToken = (token: string): AccessTokenClaims => {
  const accessSecret = requireEnv('JWT_ACCESS_SECRET');
  const payload = verify(token, accessSecret);
  if (
    typeof payload === 'string' ||
    (typeof (payload as Record<string, unknown>).companyId !== 'string' && (payload as Record<string, unknown>).companyId !== null) ||
    typeof (payload as Record<string, unknown>).context !== 'string'
  ) {
    throw new Error('Invalid access token payload');
  }
  return payload as AccessTokenClaims;
};

export const verifyRefreshToken = (token: string): RefreshTokenClaims => {
  const refreshSecret = requireEnv('JWT_REFRESH_SECRET');
  const payload = verify(token, refreshSecret);
  if (
    typeof payload === 'string' ||
    typeof (payload as Record<string, unknown>).tokenId !== 'string' ||
    typeof (payload as Record<string, unknown>).context !== 'string'
  ) {
    throw new Error('Invalid refresh token payload');
  }
  return payload as RefreshTokenClaims;
};
