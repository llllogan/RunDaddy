import { HttpClient, HttpErrorResponse, HttpHeaders } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../config/api.config';

export interface UserSummary {
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
}

export interface MembershipChoice {
  companyId: string;
  companyName: string;
  role: string;
}

const AUTH_CONTEXT = 'WEB' as const;
type AuthContext = typeof AUTH_CONTEXT;

interface SessionPayload {
  user: UserSummary;
  company: CompanySummary;
}

interface Session {
  user: UserSummary;
  company: CompanySummary;
}

interface ProfileResponse {
  user: UserSummary;
  company: CompanySummary;
}

interface CompanyMembershipResponse {
  company: {
    id: string;
    name: string;
    createdAt?: string;
    updatedAt?: string;
  };
  role: string;
}



export interface RegisterInput {
  companyName: string;
  userFirstName: string;
  userLastName: string;
  userEmail: string;
  userPassword: string;
  userPhone?: string;
}

export interface LoginInput {
  email: string;
  password: string;
  companyId?: string;
  setAsDefault?: boolean;
}

export class CompanySelectionRequiredError extends Error {
  constructor(public readonly memberships: MembershipChoice[]) {
    super('Select a company to continue.');
    this.name = 'CompanySelectionRequiredError';
  }
}

@Injectable({
  providedIn: 'root',
})
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly router = inject(Router);

  private readonly session = signal<Session | null>(null);
  private refreshPromise: Promise<void> | null = null;
  private restorePromise: Promise<boolean> | null = null;

  readonly isAuthenticated = computed(() => this.session() !== null);
  readonly user = computed(() => this.session()?.user ?? null);
  readonly company = computed(() => this.session()?.company ?? null);

  constructor() {
    void this.restoreSession();
  }

  get apiBaseUrl(): string {
    return API_BASE_URL;
  }



  async register(input: RegisterInput): Promise<void> {
    try {
      const payload = await firstValueFrom(this.http.post<SessionPayload>(`${API_BASE_URL}/auth/register`, input, { withCredentials: true }));
      this.setSession(payload);
    } catch (error) {
      this.handleHttpError(error);
    }
  }

  async login(input: LoginInput): Promise<void> {
    try {
      const payload = await firstValueFrom(
        this.http.post<SessionPayload>(`${API_BASE_URL}/auth/login`, {
          ...input,
          context: AUTH_CONTEXT,
        }, { withCredentials: true }),
      );
      this.setSession(payload);
    } catch (error) {
      if (error instanceof HttpErrorResponse && error.status === 412) {
        const memberships = this.extractMembershipChoices(error.error);
        if (memberships.length) {
          throw new CompanySelectionRequiredError(memberships);
        }
      }
      this.handleHttpError(error);
    }
  }

  async switchCompany(companyId: string, options: { persist?: boolean } = {}): Promise<void> {
    const persist = options.persist ?? true;

    try {
      const payload = await firstValueFrom(
        this.http.post<SessionPayload>(`${API_BASE_URL}/auth/switch-company`, {
          companyId,
          persist,
          context: AUTH_CONTEXT,
        }, { withCredentials: true }),
      );
      this.setSession(payload);
    } catch (error) {
      this.handleHttpError(error);
    }
  }

  async listMemberships(): Promise<MembershipChoice[]> {
    try {
      const response = await firstValueFrom(
        this.http.get<CompanyMembershipResponse[]>(`${API_BASE_URL}/companies`, { withCredentials: true }),
      );
      return response
        .map((membership) => ({
          companyId: membership.company.id,
          companyName: membership.company.name,
          role: membership.role,
        }))
        .sort((a, b) => a.companyName.localeCompare(b.companyName));
    } catch (error) {
      this.handleHttpError(error);
    }
  }

  async logout(): Promise<void> {
    try {
      await firstValueFrom(this.http.post(`${API_BASE_URL}/auth/logout`, {}, { withCredentials: true }));
    } catch {
      // Ignore errors on logout
    }
    this.clearSession();
    await this.router.navigate(['/login']);
  }

  async ensureSession(): Promise<boolean> {
    if (this.session()) {
      return true;
    }
    return this.restoreSession();
  }

  private async refreshSession(): Promise<void> {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    this.refreshPromise = firstValueFrom(this.http.post<SessionPayload>(`${API_BASE_URL}/auth/refresh`, {}, { withCredentials: true }))
      .then((payload) => {
        this.setSession(payload);
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

    this.restorePromise = firstValueFrom(this.http.get<ProfileResponse>(`${API_BASE_URL}/auth/me`, { withCredentials: true }))
      .then((profile) => {
        const session: Session = {
          user: profile.user,
          company: profile.company,
        };
        this.setSession(session);
        return true;
      })
      .catch(() => false)
      .finally(() => {
        this.restorePromise = null;
      });

    return this.restorePromise;
  }

  private setSession(payload: SessionPayload): void {
    const session: Session = {
      user: payload.user,
      company: payload.company,
    };
    this.session.set(session);
  }

  private clearSession(): void {
    this.session.set(null);
  }

  private extractMembershipChoices(payload: unknown): MembershipChoice[] {
    if (!payload || typeof payload !== 'object') {
      return [];
    }

    const membershipsRaw = (payload as { memberships?: unknown }).memberships;
    if (!Array.isArray(membershipsRaw)) {
      return [];
    }

    const choices: MembershipChoice[] = [];
    for (const entry of membershipsRaw) {
      if (!entry || typeof entry !== 'object') {
        continue;
      }

      const { companyId, companyName, role } = entry as {
        companyId?: unknown;
        companyName?: unknown;
        role?: unknown;
      };
      if (typeof companyId !== 'string' || typeof companyName !== 'string' || typeof role !== 'string') {
        continue;
      }
      choices.push({ companyId, companyName, role });
    }

    return choices;
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
