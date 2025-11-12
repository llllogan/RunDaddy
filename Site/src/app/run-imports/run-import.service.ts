import { inject, Injectable } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { buildApiUrl } from '../config/runtime-env';

@Injectable({
  providedIn: 'root',
})
export class RunImportService {
  private readonly http = inject(HttpClient);

  uploadRuns(file: File): Observable<RunImportResponse> {
    const formData = new FormData();
    formData.append('file', file);

    return this.http.post<RunImportResponse>(buildApiUrl('/run-imports/runs'), formData).pipe(
      catchError((error: HttpErrorResponse) => {
        const message = error.error?.error ?? 'Unable to upload the run. Please try again.';
        return throwError(() => new Error(message));
      }),
    );
  }
}

export type RunImportSummary = {
  runs: number;
  machines: number;
  pickEntries: number;
};

export type RunImportResponse = {
  summary: RunImportSummary;
};
