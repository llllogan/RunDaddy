export enum UserRole {
  ADMIN = 'ADMIN',
  OWNER = 'OWNER',
  PICKER = 'PICKER',
}

export enum RunStatus {
  DRAFT = 'DRAFT',
  PICKING = 'PICKING',
  READY = 'READY',
  SCHEDULED = 'SCHEDULED',
  IN_PROGRESS = 'IN_PROGRESS',
  COMPLETED = 'COMPLETED',
  CANCELLED = 'CANCELLED',
  HISTORICAL = 'HISTORICAL',
}

export enum RunItemStatus {
  PENDING = 'PENDING',
  PICKED = 'PICKED',
  SKIPPED = 'SKIPPED',
}

export const isRunStatus = (value: unknown): value is RunStatus => {
  return typeof value === 'string' && (Object.values(RunStatus) as string[]).includes(value);
};

export const isRunItemStatus = (value: unknown): value is RunItemStatus => {
  return typeof value === 'string' && (Object.values(RunItemStatus) as string[]).includes(value);
};
