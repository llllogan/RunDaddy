import {
  RunStatus as PrismaRunStatus,
  RunItemStatus as PrismaRunItemStatus,
  UserRole as PrismaUserRole,
  AuthContext as PrismaAuthContext,
} from '@prisma/client';

export const RunStatus = PrismaRunStatus;
export type RunStatus = PrismaRunStatus;

export const RunItemStatus = PrismaRunItemStatus;
export type RunItemStatus = PrismaRunItemStatus;

export const UserRole = PrismaUserRole;
export type UserRole = PrismaUserRole;

export const AuthContext = PrismaAuthContext;
export type AuthContext = PrismaAuthContext;

export const isRunStatus = (value: unknown): value is RunStatus => {
  return typeof value === 'string' && (Object.values(RunStatus) as string[]).includes(value);
};

export const isRunItemStatus = (value: unknown): value is RunItemStatus => {
  return typeof value === 'string' && (Object.values(RunItemStatus) as string[]).includes(value);
};
