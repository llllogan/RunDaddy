import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../config/api.config';

export interface RunOverviewEntry {
  id: string;
  status: string;
  scheduledFor: Date | null;
  pickingStartedAt: Date | null;
  pickingEndedAt: Date | null;
  createdAt: Date;
  picker: RunPerson | null;
  runner: RunPerson | null;
}

export interface RunPerson {
  id: string;
  firstName: string | null;
  lastName: string | null;
}

interface RunOverviewResponse {
  id: string;
  status: string;
  scheduledFor: string | null;
  pickingStartedAt: string | null;
  pickingEndedAt: string | null;
  createdAt: string;
  picker: { id: string; firstName: string | null; lastName: string | null } | null;
  runner: { id: string; firstName: string | null; lastName: string | null } | null;
}

@Injectable({
  providedIn: 'root',
})
export class RunsService {
  private readonly http = inject(HttpClient);
  private parseDate(value: string | null): Date | null {
    if (!value) {
      return null;
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  async getOverview(): Promise<RunOverviewEntry[]> {
    try {
      const response = await firstValueFrom(
        this.http.get<RunOverviewResponse[]>(`${API_BASE_URL}/runs/overview`),
      );

      return response.map((run) => ({
        id: run.id,
        status: run.status,
        scheduledFor: this.parseDate(run.scheduledFor),
        pickingStartedAt: this.parseDate(run.pickingStartedAt),
        pickingEndedAt: this.parseDate(run.pickingEndedAt),
        createdAt: this.parseDate(run.createdAt) ?? new Date(),
        picker: run.picker
          ? {
              id: run.picker.id,
              firstName: run.picker.firstName,
              lastName: run.picker.lastName,
            }
          : null,
        runner: run.runner
          ? {
              id: run.runner.id,
              firstName: run.runner.firstName,
              lastName: run.runner.lastName,
            }
          : null,
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
        'Unable to load runs.';
      return new Error(message);
    }
    if (error instanceof Error) {
      return error;
    }
    return new Error('Unable to load runs.');
  }
}
