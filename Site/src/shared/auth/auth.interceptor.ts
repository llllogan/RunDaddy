import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, switchMap, throwError } from 'rxjs';
import { AuthService } from '@shared/auth/auth.service';
import { buildApiUrl } from '@shared/config/runtime-env';

const AUTH_ENDPOINTS = [
  '/auth/login',
  '/auth/refresh',
  '/auth/logout',
  '/auth/me',
].map((path) => buildApiUrl(path));

const isAuthEndpoint = (url: string): boolean => {
  const sanitized = url.split('?')[0] ?? url;
  return AUTH_ENDPOINTS.some((endpoint) => sanitized === endpoint);
};

export const credentialsInterceptor: HttpInterceptorFn = (req, next) => {
  const request = req.withCredentials ? req : req.clone({ withCredentials: true });
  return next(request);
};

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  return next(req).pipe(
    catchError((error: HttpErrorResponse) => {
      if (error.status !== 401 || isAuthEndpoint(req.url)) {
        return throwError(() => error);
      }

      return authService.refreshSession().pipe(
        switchMap(() => next(req)),
        catchError((refreshError) => {
          authService.handleSessionExpiry();
          return throwError(() => refreshError);
        }),
      );
    }),
  );
};
