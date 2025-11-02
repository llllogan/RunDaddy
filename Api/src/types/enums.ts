export const RunStatus = {
  DRAFT: 'DRAFT',
  PICKING: 'PICKING',
  READY: 'READY',
  SCHEDULED: 'SCHEDULED',
  IN_PROGRESS: 'IN_PROGRESS',
  COMPLETED: 'COMPLETED',
  CANCELLED: 'CANCELLED',
  HISTORICAL: 'HISTORICAL',
} as const;

export type RunStatus = typeof RunStatus[keyof typeof RunStatus];

export const RunItemStatus = {
  PENDING: 'PENDING',
  PICKED: 'PICKED',
  SKIPPED: 'SKIPPED',
} as const;

export type RunItemStatus = typeof RunItemStatus[keyof typeof RunItemStatus];

export const UserRole = {
  ADMIN: 'ADMIN',
  OWNER: 'OWNER',
  PICKER: 'PICKER',
} as const;

export type UserRole = typeof UserRole[keyof typeof UserRole];

export const AuthContext = {
  WEB: 'WEB',
  APP: 'APP',
} as const;

export type AuthContext = typeof AuthContext[keyof typeof AuthContext];

export const isRunStatus = (value: unknown): value is RunStatus => {
  return typeof value === 'string' && (Object.values(RunStatus) as string[]).includes(value);
};

export const isRunItemStatus = (value: unknown): value is RunItemStatus => {
  return typeof value === 'string' && (Object.values(RunItemStatus) as string[]).includes(value);
};
