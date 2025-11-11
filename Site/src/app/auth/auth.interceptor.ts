import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthService } from './auth.service';
import { catchError, switchMap } from 'rxjs/operators';
import { throwError, from } from 'rxjs';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);

  return next(req).pipe(
    catchError((error) => {
      if (error.status === 401 && !req.headers.has('X-Retry')) {
        // Try to refresh the session
        return authService.refreshSessionObservable().pipe(
          switchMap((payload) => {
            // Update session with new tokens
            authService.updateSession(payload);
            // Retry the request with a retry header to prevent infinite loops
            const retryReq = req.clone({
              headers: req.headers.set('X-Retry', 'true')
            });
            return next(retryReq);
          }),
          catchError(() => {
            // Refresh failed, log out
            authService.logout();
            return throwError(() => error);
          })
        );
      } else if (error.status === 401 && req.headers.has('X-Retry')) {
        // Already tried refresh, log out
        authService.logout();
      }
      return throwError(() => error);
    })
  );
};
