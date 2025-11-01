import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../config/api.config';

export interface RunOverviewEntry {
  id: string;
  status: string;
  pickerId: string | null;
  runnerId: string | null;
  companyId: string;
  pickingStartedAt: Date | null;
  pickingEndedAt: Date | null;
  scheduledFor: Date | null;
  createdAt: Date;
}

interface RunOverviewResponse {
  id: string;
  status: string;
  pickerId: string | null;
  runnerId: string | null;
  companyId: string;
  pickingStartedAt: string | null;
  pickingEndedAt: string | null;
  scheduledFor: string | null;
  createdAt: string;
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
        pickerId: run.pickerId,
        runnerId: run.runnerId,
        companyId: run.companyId,
        pickingStartedAt: this.parseDate(run.pickingStartedAt),
        pickingEndedAt: this.parseDate(run.pickingEndedAt),
        scheduledFor: this.parseDate(run.scheduledFor),
        createdAt: this.parseDate(run.createdAt) ?? new Date(),
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
        'Unable to load run data.';
      return new Error(message);
    }
    if (error instanceof Error) {
      return error;
    }
    return new Error('Unable to load run data.');
  }
}
