import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../config/api.config';

export type RunAssignmentRole = 'PICKER' | 'RUNNER';

export interface RunOverviewEntry {
  id: string;
  status: string;
  pickerId: string | null;
  pickerFirstName: string | null;
  pickerLastName: string | null;
  runnerId: string | null;
  runnerFirstName: string | null;
  runnerLastName: string | null;
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
  pickerFirstName: string | null;
  pickerLastName: string | null;
  runnerId: string | null;
  runnerFirstName: string | null;
  runnerLastName: string | null;
  companyId: string;
  pickingStartedAt: string | null;
  pickingEndedAt: string | null;
  scheduledFor: string | null;
  createdAt: string;
}

interface RunAssignmentResponse {
  id: string;
  status: string;
  companyId: string;
  pickingStartedAt: string | null;
  pickingEndedAt: string | null;
  scheduledFor: string | null;
  createdAt: string;
  picker: {
    id: string;
    firstName: string | null;
    lastName: string | null;
  } | null;
  runner: {
    id: string;
    firstName: string | null;
    lastName: string | null;
  } | null;
}

@Injectable({
  providedIn: 'root',
})
export class RunsService {
  private readonly http = inject(HttpClient);

  async getOverview(): Promise<RunOverviewEntry[]> {
    try {
      const response = await firstValueFrom(
        this.http.get<RunOverviewResponse[]>(`${API_BASE_URL}/runs/overview`),
      );
      return response.map((run) => this.toRunOverviewEntry(run));
    } catch (error) {
      throw this.toError(error);
    }
  }

  async assignParticipant(runId: string, userId: string, role: RunAssignmentRole): Promise<RunOverviewEntry> {
    try {
      const response = await firstValueFrom(
        this.http.post<RunAssignmentResponse>(`${API_BASE_URL}/runs/${runId}/assignment`, {
          userId,
          role,
        }),
      );

      const normalized: RunOverviewResponse = {
        id: response.id,
        status: response.status,
        companyId: response.companyId,
        pickerId: response.picker?.id ?? null,
        pickerFirstName: response.picker?.firstName ?? null,
        pickerLastName: response.picker?.lastName ?? null,
        runnerId: response.runner?.id ?? null,
        runnerFirstName: response.runner?.firstName ?? null,
        runnerLastName: response.runner?.lastName ?? null,
        pickingStartedAt: response.pickingStartedAt,
        pickingEndedAt: response.pickingEndedAt,
        scheduledFor: response.scheduledFor,
        createdAt: response.createdAt,
      };

      return this.toRunOverviewEntry(normalized);
    } catch (error) {
      throw this.toError(error);
    }
  }

  private toRunOverviewEntry(run: RunOverviewResponse): RunOverviewEntry {
    return {
      id: run.id,
      status: run.status,
      companyId: run.companyId,
      pickerId: run.pickerId,
      pickerFirstName: run.pickerFirstName,
      pickerLastName: run.pickerLastName,
      runnerId: run.runnerId,
      runnerFirstName: run.runnerFirstName,
      runnerLastName: run.runnerLastName,
      pickingStartedAt: this.parseDate(run.pickingStartedAt),
      pickingEndedAt: this.parseDate(run.pickingEndedAt),
      scheduledFor: this.parseDate(run.scheduledFor),
      createdAt: this.parseDate(run.createdAt) ?? new Date(),
    };
  }

  private parseDate(value: string | null): Date | null {
    if (!value) {
      return null;
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
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
