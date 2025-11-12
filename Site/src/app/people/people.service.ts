import { inject, Injectable } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { catchError, map } from 'rxjs/operators';
import { buildApiUrl } from '../config/runtime-env';
import { UserRole } from '../auth/auth.service';

export interface CompanyPerson {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  phone?: string | null;
  role: UserRole;
  createdAt: string;
  updatedAt: string;
}

@Injectable({ providedIn: 'root' })
export class PeopleService {
  private readonly http = inject(HttpClient);

  listCompanyPeople(): Observable<CompanyPerson[]> {
    return this.http.get<CompanyPerson[]>(buildApiUrl('/users')).pipe(catchError((error) => this.handleError(error)));
  }

  updatePersonRole(userId: string, role: UserRole): Observable<CompanyPerson> {
    return this.http
      .patch<CompanyPerson>(buildApiUrl(`/users/${userId}`), { role })
      .pipe(catchError((error) => this.handleError(error)));
  }

  removePerson(userId: string): Observable<void> {
    return this.http
      .delete<void>(buildApiUrl(`/users/${userId}`))
      .pipe(
        map(() => void 0),
        catchError((error) => this.handleError(error)),
      );
  }

  private handleError(error: HttpErrorResponse) {
    const message = error.error?.error ?? 'Unable to complete that request. Please try again.';
    return throwError(() => new Error(message));
  }
}
