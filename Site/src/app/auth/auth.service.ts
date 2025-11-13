import { Injectable } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Router } from '@angular/router';
import { BehaviorSubject, Observable, catchError, finalize, map, of, shareReplay, take, tap, throwError } from 'rxjs';
import { buildApiUrl } from '../config/runtime-env';

export type UserRole = 'ADMIN' | 'OWNER' | 'PICKER';

type LoginResponse = {
  user: SessionUser;
  company: SessionCompany | null;
  platformAdminCompanyId: string | null;
};

type SessionMeResponse = {
  user: SessionUser;
  currentCompany: SessionCompany | null;
  companies: SessionCompany[];
  platformAdminCompanyId: string | null;
};

export interface SessionUser {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: UserRole;
  phone?: string | null;
  platformAdmin: boolean;
}

export interface SessionCompany {
  id: string;
  name: string;
  role?: UserRole;
}

export interface AuthSession {
  user: SessionUser;
  company: SessionCompany | null;
  companies?: SessionCompany[];
  platformAdminCompanyId: string | null;
}

export interface LoginPayload {
  email: string;
  password: string;
  companyId?: string;
  setAsDefault?: boolean;
}

export interface RegisterPayload {
  companyName: string;
  userFirstName: string;
  userLastName: string;
  userEmail: string;
  userPassword: string;
  userPhone?: string;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly sessionSubject = new BehaviorSubject<AuthSession | null>(null);
  readonly session$ = this.sessionSubject.asObservable();

  private readonly bootstrappedSubject = new BehaviorSubject<boolean>(false);
  readonly isBootstrapped$ = this.bootstrappedSubject.asObservable();

  private readonly loadingSubject = new BehaviorSubject<boolean>(false);
  readonly isLoading$ = this.loadingSubject.asObservable();

  private refreshRequest$?: Observable<AuthSession>;
  private bootstrapRequest$?: Observable<AuthSession | null>;

  constructor(private readonly http: HttpClient, private readonly router: Router) {}

  ensureBootstrap(): void {
    if (this.bootstrappedSubject.value || this.bootstrapRequest$) {
      return;
    }

    this.bootstrapSession().pipe(take(1)).subscribe({
      error: () => {
        /* handled inside bootstrapSession */
      },
    });
  }

  bootstrapSession(): Observable<AuthSession | null> {
    if (!this.bootstrapRequest$) {
      this.loadingSubject.next(true);
      this.bootstrapRequest$ = this.http
        .get<SessionMeResponse>(buildApiUrl('/auth/me'))
        .pipe(
          map((response) => this.mapSessionFromMeResponse(response)),
          tap((session) => this.sessionSubject.next(session)),
          catchError((error: HttpErrorResponse) => {
            if (error.status === 401) {
              this.sessionSubject.next(null);
              return of(null);
            }
            return throwError(() => error);
          }),
          finalize(() => {
            this.loadingSubject.next(false);
            this.bootstrappedSubject.next(true);
            this.bootstrapRequest$ = undefined;
          }),
          shareReplay(1),
        );
    }

    return this.bootstrapRequest$;
  }

  login(payload: LoginPayload): Observable<AuthSession> {
    const body = { ...payload, context: 'WEB' as const };
    return this.http.post<LoginResponse>(buildApiUrl('/auth/login'), body).pipe(
      map((response) => this.mapSessionFromAuthResponse(response)),
      tap((session) => {
        this.sessionSubject.next(session);
        this.bootstrappedSubject.next(true);
      }),
    );
  }

  registerCompanyAccount(payload: RegisterPayload): Observable<AuthSession> {
    return this.http.post<LoginResponse>(buildApiUrl('/auth/register'), payload).pipe(
      map((response) => this.mapSessionFromAuthResponse(response)),
      tap((session) => {
        this.sessionSubject.next(session);
        this.bootstrappedSubject.next(true);
      }),
    );
  }

  logout(): Observable<void> {
    return this.http.post(buildApiUrl('/auth/logout'), {}).pipe(
      map(() => void 0),
      catchError(() => of(void 0)),
      tap(() => this.handleSessionExpiry()),
    );
  }

  refreshSession(): Observable<AuthSession> {
    if (!this.refreshRequest$) {
      this.refreshRequest$ = this.http
        .post<LoginResponse>(buildApiUrl('/auth/refresh'), {})
        .pipe(
          map((response) => this.mapSessionFromAuthResponse(response)),
          tap((session) => {
            this.sessionSubject.next(session);
            if (!this.bootstrappedSubject.value) {
              this.bootstrappedSubject.next(true);
            }
          }),
          finalize(() => {
            this.refreshRequest$ = undefined;
          }),
          shareReplay(1),
        );
    }

    return this.refreshRequest$;
  }

  handleSessionExpiry(): void {
    if (this.sessionSubject.value !== null) {
      this.sessionSubject.next(null);
    }
    if (!this.bootstrappedSubject.value) {
      this.bootstrappedSubject.next(true);
    }
    void this.router.navigate(['/login']);
  }

  private mapSessionFromAuthResponse(response: LoginResponse): AuthSession {
    return {
      user: response.user,
      company: response.company ?? null,
      platformAdminCompanyId: response.platformAdminCompanyId ?? null,
    };
  }

  private mapSessionFromMeResponse(response: SessionMeResponse): AuthSession {
    return {
      user: response.user,
      company: response.currentCompany ?? null,
      companies: response.companies,
      platformAdminCompanyId: response.platformAdminCompanyId ?? null,
    };
  }
}
