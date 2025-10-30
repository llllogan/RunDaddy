import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../config/api.config';

export interface DashboardUser {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  phone: string | null;
  role: string;
  createdAt: Date | null;
  updatedAt: Date | null;
}

interface UsersResponseItem {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  phone: string | null;
  role: string;
  createdAt: string;
  updatedAt: string;
}

@Injectable({
  providedIn: 'root',
})
export class UsersService {
  private readonly http = inject(HttpClient);
  private parseDate(value: string | null | undefined): Date | null {
    if (!value) {
      return null;
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  async listUsers(): Promise<DashboardUser[]> {
    try {
      const response = await firstValueFrom(
        this.http.get<UsersResponseItem[]>(`${API_BASE_URL}/users`),
      );

      return response.map((user) => ({
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        phone: user.phone,
        role: user.role,
        createdAt: this.parseDate(user.createdAt),
        updatedAt: this.parseDate(user.updatedAt),
      }));
    } catch (error) {
      throw this.toError(error);
    }
  }

  private toError(error: unknown): Error {
    if (error instanceof HttpErrorResponse) {
      const message =
        (typeof error.error === 'object' &&
          error.error &&
          'error' in error.error &&
          typeof error.error.error === 'string'
          ? error.error.error
          : null) ??
        error.message ??
        'Unable to load users.';
      return new Error(message);
    }
    if (error instanceof Error) {
      return error;
    }
    return new Error('Unable to load users.');
  }
}
