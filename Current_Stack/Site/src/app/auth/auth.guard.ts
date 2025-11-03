import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from './auth.service';

export const authGuard: CanActivateFn = async (_route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);

  const authenticated = await auth.ensureSession();
  if (authenticated) {
    return true;
  }

  const queryParams = state.url && state.url !== '/' ? { returnUrl: state.url } : undefined;
  return router.createUrlTree(['/login'], { queryParams });
};
