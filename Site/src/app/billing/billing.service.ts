import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { buildApiUrl } from '../config/runtime-env';

type BillingCheckoutResponse = {
  url: string | null;
};

@Injectable({ providedIn: 'root' })
export class BillingService {
  constructor(private readonly http: HttpClient) {}

  createCheckoutSession(): Observable<BillingCheckoutResponse> {
    return this.http.post<BillingCheckoutResponse>(buildApiUrl('/billing/checkout'), {});
  }
}
