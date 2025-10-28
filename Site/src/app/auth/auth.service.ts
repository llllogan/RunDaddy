import { HttpClient, HttpErrorResponse, HttpHeaders } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../config/api.config';

export interface AdminSummary {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: string;
  phone?: string | null;
}

export interface CompanySummary {
  id: string;
  name: string;
  slug: string;
}

interface TokenPayload {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: string;
  refreshTokenExpiresAt: string;
}

interface SessionPayload {
  admin: AdminSummary;
  company: CompanySummary;
  tokens: TokenPayload;
}

interface TokenSet {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: Date;
  refreshTokenExpiresAt: Date;
}

interface Session {
  admin: AdminSummary;
  company: CompanySummary;
  tokens: TokenSet;
}

interface ProfileResponse {
  admin: AdminSummary;
  company: CompanySummary;
}

interface StoredSession {
  admin: AdminSummary;
  company: CompanySummary;
  tokens: {
    accessToken: string;
    refreshToken: string;
    accessTokenExpiresAt: string;
    refreshTokenExpiresAt: string;
  };
}

export interface RegisterInput {
  companyName: string;
  companyDescription?: string;
  adminFirstName: string;
  adminLastName: string;
  adminEmail: string;
  adminPassword: string;
  adminPhone?: string;
}

export interface LoginInput {
  email: string;
  password: string;
}

@Injectable({
  providedIn: 'root',
})
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly router = inject(Router);

  private readonly storageKey = 'rundaddy:auth';
  private readonly session = signal<Session | null>(null);
  private refreshTimer: ReturnType<typeof setTimeout> | null = null;
  private refreshPromise: Promise<void> | null = null;
  private restorePromise: Promise<boolean> | null = null;

  readonly isAuthenticated = computed(() => this.session() !== null);
  readonly admin = computed(() => this.session()?.admin ?? null);
  readonly company = computed(() => this.session()?.company ?? null);

  constructor() {
    void this.restoreSession();
  }

  get apiBaseUrl(): string {
    return API_BASE_URL;
  }

  getAccessToken(): string | null {
    const current = this.session();
    if (!current) {
      return null;
    }

    if (current.tokens.accessTokenExpiresAt.getTime() <= Date.now()) {
      return null;
    }

    return current.tokens.accessToken;
  }

  async register(input: RegisterInput): Promise<void> {
    try {
      const payload = await firstValueFrom(this.http.post<SessionPayload>(`${API_BASE_URL}/auth/register`, input));
      this.applySessionPayload(payload);
    } catch (error) {
      this.handleHttpError(error);
    }
  }

  async login(input: LoginInput): Promise<void> {
    try {
      const payload = await firstValueFrom(this.http.post<SessionPayload>(`${API_BASE_URL}/auth/login`, input));
      this.applySessionPayload(payload);
    } catch (error) {
      this.handleHttpError(error);
    }
  }

  async logout(): Promise<void> {
    this.clearSession();
    await this.router.navigate(['/login']);
  }

  async ensureSession(): Promise<boolean> {
    const current = this.session();
    if (current) {
      if (current.tokens.accessTokenExpiresAt.getTime() <= Date.now() + 5_000) {
        try {
          await this.refreshSession();
          return this.session() !== null;
        } catch {
          return false;
        }
      }
      return true;
    }
    return this.restoreSession();
  }

  private async refreshSession(): Promise<void> {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    const current = this.session();
    if (!current) {
      throw new Error('No active session to refresh');
    }

    const request = firstValueFrom(
      this.http.post<SessionPayload>(`${API_BASE_URL}/auth/refresh`, {
        refreshToken: current.tokens.refreshToken,
      }),
    );

    this.refreshPromise = request
      .then((payload) => {
        this.applySessionPayload(payload);
      })
      .catch((error) => {
        this.clearSession();
        this.handleHttpError(error);
      })
      .finally(() => {
        this.refreshPromise = null;
      });

    return this.refreshPromise;
  }

  private async restoreSession(): Promise<boolean> {
    if (this.session()) {
      return true;
    }

    if (this.restorePromise) {
      return this.restorePromise;
    }

    const stored = this.readStoredSession();
    if (!stored) {
      return false;
    }

    this.restorePromise = (async () => {
      try {
        const now = Date.now();
        const needsRefresh = stored.tokens.accessTokenExpiresAt.getTime() <= now + 5_000;

        if (needsRefresh) {
          const refreshed = await firstValueFrom(
            this.http.post<SessionPayload>(`${API_BASE_URL}/auth/refresh`, {
              refreshToken: stored.tokens.refreshToken,
            }),
          );
          this.applySessionPayload(refreshed);
          return true;
        }

        const headers = new HttpHeaders({
          Authorization: `Bearer ${stored.tokens.accessToken}`,
        });
        const profile = await firstValueFrom(this.http.get<ProfileResponse>(`${API_BASE_URL}/auth/me`, { headers }));
        const session: Session = {
          admin: profile.admin,
          company: profile.company,
          tokens: stored.tokens,
        };
        this.setSession(session);
        return true;
      } catch {
        this.clearStoredSession();
        return false;
      }
    })().finally(() => {
      this.restorePromise = null;
    });

    return this.restorePromise;
  }

  private applySessionPayload(payload: SessionPayload): void {
    const session = this.mapSession(payload);
    this.setSession(session);
  }

  private setSession(session: Session, options: { persist?: boolean; schedule?: boolean } = {}): void {
    const persist = options.persist ?? true;
    const schedule = options.schedule ?? true;

    this.session.set(session);

    if (persist) {
      this.persistSession(session);
    }

    if (schedule) {
      this.scheduleRefresh(session.tokens);
    }
  }

  private mapSession(payload: SessionPayload): Session {
    return {
      admin: payload.admin,
      company: payload.company,
      tokens: {
        accessToken: payload.tokens.accessToken,
        refreshToken: payload.tokens.refreshToken,
        accessTokenExpiresAt: new Date(payload.tokens.accessTokenExpiresAt),
        refreshTokenExpiresAt: new Date(payload.tokens.refreshTokenExpiresAt),
      },
    };
  }

  private scheduleRefresh(tokens: TokenSet): void {
    this.cancelScheduledRefresh();
    const bufferMs = 30_000;
    const expiresIn = tokens.accessTokenExpiresAt.getTime() - Date.now();

    if (expiresIn <= 0) {
      this.refreshSoon();
      return;
    }

    const delay = Math.max(1_000, expiresIn - bufferMs);
    this.refreshTimer = setTimeout(() => {
      this.refreshSoon();
    }, delay);
  }

  private refreshSoon(): void {
    void this.refreshSession().catch(() => undefined);
  }

  private cancelScheduledRefresh(): void {
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  private persistSession(session: Session): void {
    if (typeof localStorage === 'undefined') {
      return;
    }
    const stored: StoredSession = {
      admin: session.admin,
      company: session.company,
      tokens: {
        accessToken: session.tokens.accessToken,
        refreshToken: session.tokens.refreshToken,
        accessTokenExpiresAt: session.tokens.accessTokenExpiresAt.toISOString(),
        refreshTokenExpiresAt: session.tokens.refreshTokenExpiresAt.toISOString(),
      },
    };
    localStorage.setItem(this.storageKey, JSON.stringify(stored));
  }

  private readStoredSession(): Session | null {
    if (typeof localStorage === 'undefined') {
      return null;
    }
    const raw = localStorage.getItem(this.storageKey);
    if (!raw) {
      return null;
    }
    try {
      const parsed = JSON.parse(raw) as StoredSession;
      return {
        admin: parsed.admin,
        company: parsed.company,
        tokens: {
          accessToken: parsed.tokens.accessToken,
          refreshToken: parsed.tokens.refreshToken,
          accessTokenExpiresAt: new Date(parsed.tokens.accessTokenExpiresAt),
          refreshTokenExpiresAt: new Date(parsed.tokens.refreshTokenExpiresAt),
        },
      };
    } catch {
      this.clearStoredSession();
      return null;
    }
  }

  private clearSession(): void {
    this.cancelScheduledRefresh();
    this.session.set(null);
    this.clearStoredSession();
  }

  private clearStoredSession(): void {
    if (typeof localStorage === 'undefined') {
      return;
    }
    localStorage.removeItem(this.storageKey);
  }

  private handleHttpError(error: unknown): never {
    if (error instanceof HttpErrorResponse) {
      const message =
        (typeof error.error === 'object' && error.error && 'error' in error.error && typeof error.error.error === 'string'
          ? error.error.error
          : null) ??
        error.message ??
        'Unable to complete request.';
      throw new Error(message);
    }
    if (error instanceof Error) {
      throw error;
    }
    throw new Error('Unexpected error occurred.');
  }
}
