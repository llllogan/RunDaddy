import { Injectable } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { environment } from '../../environments/environment';

export interface InviteCode {
  id: string;
  code: string;
  companyId: string;
  role: 'ADMIN' | 'OWNER' | 'PICKER';
  createdBy: string;
  expiresAt: string;
  usedBy?: string;
  usedAt?: string;
  createdAt: string;
  company?: {
    name: string;
  };
  creator?: {
    firstName?: string;
    lastName?: string;
  };
  usedByUser?: {
    firstName?: string;
    lastName?: string;
  };
}

export interface CreateInviteCodeRequest {
  companyId: string;
  role: 'ADMIN' | 'OWNER' | 'PICKER';
}

export interface UseInviteCodeRequest {
  code: string;
}

export interface UseInviteCodeResponse {
  message: string;
  membership: {
    id: string;
    userId: string;
    companyId: string;
    role: 'ADMIN' | 'OWNER' | 'PICKER';
    company?: {
      name: string;
    };
  };
}

@Injectable({
  providedIn: 'root'
})
export class InviteCodesService {
  private readonly apiUrl = environment.apiConfig.baseUrl;

  constructor(private http: HttpClient) {}

  generateInviteCode(request: CreateInviteCodeRequest): Observable<InviteCode> {
    return this.http.post<InviteCode>(`${this.apiUrl}/invite-codes/generate`, request).pipe(
      catchError(this.handleError)
    );
  }

  useInviteCode(request: UseInviteCodeRequest): Observable<UseInviteCodeResponse> {
    return this.http.post<UseInviteCodeResponse>(`${this.apiUrl}/invite-codes/use`, request).pipe(
      catchError(this.handleError)
    );
  }

  getInviteCodes(companyId: string): Observable<InviteCode[]> {
    return this.http.get<InviteCode[]>(`${this.apiUrl}/invite-codes/company/${companyId}`).pipe(
      catchError(this.handleError)
    );
  }

  private handleError(error: HttpErrorResponse) {
    let errorMessage = 'An error occurred';
    
    if (error.error instanceof ErrorEvent) {
      // Client-side error
      errorMessage = error.error.message;
    } else {
      // Server-side error
      errorMessage = error.error?.error || error.message;
    }
    
    return throwError(() => new Error(errorMessage));
  }
}