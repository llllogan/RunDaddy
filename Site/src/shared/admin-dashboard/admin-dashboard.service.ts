import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { inject, Injectable } from '@angular/core';
import { Observable, throwError } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { buildApiUrl } from '@shared/config/runtime-env';
import { ADMIN_DASHBOARD_API_CONFIG } from './admin-dashboard-api-config';

export interface AdminCompanySummary {
  id: string;
  name: string;
  timeZone?: string | null;
  createdAt: string;
  updatedAt: string;
  memberCount: number;
  runCount: number;
  activeRunCount: number;
  lastRunAt?: string | null;
}

export interface AdminCompanyMember {
  id: string;
  userId: string;
  role: 'ADMIN' | 'OWNER' | 'PICKER';
  firstName: string;
  lastName: string;
  email: string;
  phone?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AdminCompanyRun {
  id: string;
  status: string;
  scheduledFor?: string | null;
  picker?: { id: string; name: string } | null;
  runner?: { id: string; name: string } | null;
}

export interface AdminCompanyDetail {
  id: string;
  name: string;
  timeZone?: string | null;
  createdAt: string;
  updatedAt: string;
  memberCount: number;
  runCount: number;
  activeRunCount: number;
  members: AdminCompanyMember[];
  recentRuns: AdminCompanyRun[];
}

@Injectable({ providedIn: 'root' })
export class AdminDashboardService {
  private readonly http = inject(HttpClient);
  private readonly apiConfig = inject(ADMIN_DASHBOARD_API_CONFIG);

  getCompanies(): Observable<AdminCompanySummary[]> {
    return this.http
      .get<AdminCompanySummary[]>(buildApiUrl(`${this.apiConfig.basePath}/companies`))
      .pipe(catchError((error) => this.handleError(error, 'Unable to load company list. Please try again.')));
  }

  getCompany(companyId: string): Observable<AdminCompanyDetail> {
    return this.http
      .get<AdminCompanyDetail>(buildApiUrl(`${this.apiConfig.basePath}/companies/${companyId}`))
      .pipe(
        catchError((error) => this.handleError(error, 'Unable to load company details. Please try again.')),
      );
  }

  deleteCompany(companyId: string): Observable<void> {
    if (!this.apiConfig.allowDelete) {
      return throwError(() => new Error('Company deletion is disabled.'));
    }
    return this.http
      .delete<void>(buildApiUrl(`${this.apiConfig.basePath}/companies/${companyId}`))
      .pipe(catchError((error) => this.handleError(error, 'Unable to delete company. Please try again.')));
  }

  private handleError(error: HttpErrorResponse, fallbackMessage = 'Unable to load admin data. Please try again.') {
    const message = error.error?.error ?? fallbackMessage;
    return throwError(() => new Error(message));
  }
}
