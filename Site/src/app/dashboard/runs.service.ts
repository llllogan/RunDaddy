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

interface RunDetailResponse extends RunOverviewResponse {
  companyId: string;
  pickEntries: Array<{
    id: string;
    status: string;
    count: number;
    pickedAt: string | null;
    coilItem: {
      id: string;
      par: number;
      coil: {
        id: string;
        code: string;
        machine: {
          id: string;
          code: string;
          description: string | null;
          locationId: string | null;
        };
      };
      sku: {
        id: string;
        code: string;
        name: string;
        type: string;
      };
    };
  }>;
}

export interface RunDetail extends RunOverviewEntry {
  pickEntries: RunDetailPickEntry[];
}

export interface RunDetailPickEntry {
  id: string;
  status: string;
  count: number;
  pickedAt: Date | null;
  par: number;
  sku: {
    id: string;
    code: string;
    name: string;
    type: string;
  };
  coil: {
    id: string;
    code: string;
    machine: {
      id: string;
      code: string;
      description: string | null;
      locationId: string | null;
    };
  };
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

  async getRunDetail(runId: string): Promise<RunDetail> {
    try {
      const response = await firstValueFrom(
        this.http.get<RunDetailResponse>(`${API_BASE_URL}/runs/${runId}`),
      );

      const base: RunDetail = {
        id: response.id,
        status: response.status,
        scheduledFor: this.parseDate(response.scheduledFor),
        pickingStartedAt: this.parseDate(response.pickingStartedAt),
        pickingEndedAt: this.parseDate(response.pickingEndedAt),
        createdAt: this.parseDate(response.createdAt) ?? new Date(),
        picker: response.picker
          ? {
              id: response.picker.id,
              firstName: response.picker.firstName,
              lastName: response.picker.lastName,
            }
          : null,
        runner: response.runner
          ? {
              id: response.runner.id,
              firstName: response.runner.firstName,
              lastName: response.runner.lastName,
            }
          : null,
        pickEntries: response.pickEntries.map((entry) => ({
          id: entry.id,
          status: entry.status,
          count: entry.count,
          pickedAt: this.parseDate(entry.pickedAt),
          par: entry.coilItem.par,
          sku: {
            id: entry.coilItem.sku.id,
            code: entry.coilItem.sku.code,
            name: entry.coilItem.sku.name,
            type: entry.coilItem.sku.type,
          },
          coil: {
            id: entry.coilItem.coil.id,
            code: entry.coilItem.coil.code,
            machine: {
              id: entry.coilItem.coil.machine.id,
              code: entry.coilItem.coil.machine.code,
              description: entry.coilItem.coil.machine.description,
              locationId: entry.coilItem.coil.machine.locationId,
            },
          },
        })),
      };

      return base;
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
