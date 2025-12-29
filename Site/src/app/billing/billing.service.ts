import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { buildApiUrl } from '../config/runtime-env';

type BillingCheckoutResponse = {
  url: string | null;
};

export type BillingStatusResponse = {
  billingStatus: string;
  currentPeriodEnd: string | null;
  tierId: string;
};

@Injectable({ providedIn: 'root' })
export class BillingService {
  constructor(private readonly http: HttpClient) {}

  createCheckoutSession(tierId?: string): Observable<BillingCheckoutResponse> {
    const payload = tierId ? { tierId } : {};
    return this.http.post<BillingCheckoutResponse>(buildApiUrl('/billing/checkout'), payload);
  }

  createPortalSession(): Observable<BillingCheckoutResponse> {
    return this.http.post<BillingCheckoutResponse>(buildApiUrl('/billing/portal'), {});
  }

  getStatus(): Observable<BillingStatusResponse> {
    return this.http.get<BillingStatusResponse>(buildApiUrl('/billing/status'));
  }
}
