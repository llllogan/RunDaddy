export const RunStatus = {
  CREATED: 'CREATED',
  PENDING_FRESH: 'PENDING_FRESH',
  PICKING: 'PICKING',
  READY: 'READY',
} as const;

export type RunStatus = typeof RunStatus[keyof typeof RunStatus];

export const UserRole = {
  ADMIN: 'ADMIN',
  OWNER: 'OWNER',
  PICKER: 'PICKER',
} as const;

export type UserRole = typeof UserRole[keyof typeof UserRole];

export const AccountRole = {
  LIGHTHOUSE: 'LIGHTHOUSE',
} as const;

export type AccountRole = typeof AccountRole[keyof typeof AccountRole];

export const AuthContext = {
  WEB: 'WEB',
  APP: 'APP',
} as const;

export type AuthContext = typeof AuthContext[keyof typeof AuthContext];

export const BillingStatus = {
  ACTIVE: 'ACTIVE',
  TRIALING: 'TRIALING',
  INCOMPLETE: 'INCOMPLETE',
  PAST_DUE: 'PAST_DUE',
  UNPAID: 'UNPAID',
  CANCELED: 'CANCELED',
} as const;

export type BillingStatus = typeof BillingStatus[keyof typeof BillingStatus];

export const isRunStatus = (value: unknown): value is RunStatus => {
  return typeof value === 'string' && (Object.values(RunStatus) as string[]).includes(value);
};
