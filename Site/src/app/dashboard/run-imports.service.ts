import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../config/api.config';

export interface RunImportSummary {
  runs: number;
  machines: number;
  pickEntries: number;
}

export interface RunImportPreview {
  summary: RunImportSummary;
  workbook: unknown;
  run: {
    id: string;
    status: string;
    scheduledFor: string | null;
    createdAt: string;
  };
}

@Injectable({
  providedIn: 'root',
})
export class RunImportsService {
  private readonly http = inject(HttpClient);

  async uploadRun(file: File): Promise<RunImportPreview> {
    const formData = new FormData();
    formData.append('file', file, file.name);

    try {
      return await firstValueFrom(
        this.http.post<RunImportPreview>(`${API_BASE_URL}/run-imports/runs`, formData, { withCredentials: true }),
      );
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
        'Unable to upload workbook.';
      return new Error(message);
    }
    if (error instanceof Error) {
      return error;
    }
    return new Error('Unable to upload workbook.');
  }
}
