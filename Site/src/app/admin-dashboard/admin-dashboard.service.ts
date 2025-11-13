import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { inject, Injectable } from '@angular/core';
import { Observable, throwError } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { buildApiUrl } from '../config/runtime-env';

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

  getCompanies(): Observable<AdminCompanySummary[]> {
    return this.http
      .get<AdminCompanySummary[]>(buildApiUrl('/admin/companies'))
      .pipe(catchError((error) => this.handleError(error)));
  }

  getCompany(companyId: string): Observable<AdminCompanyDetail> {
    return this.http
      .get<AdminCompanyDetail>(buildApiUrl(`/admin/companies/${companyId}`))
      .pipe(catchError((error) => this.handleError(error)));
  }

  private handleError(error: HttpErrorResponse) {
    const message = error.error?.error ?? 'Unable to load admin data. Please try again.';
    return throwError(() => new Error(message));
  }
}
