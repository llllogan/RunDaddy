import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { combineLatest, filter, map, take } from 'rxjs';
import { AuthService } from './auth.service';

export const authGuard: CanActivateFn = () => {
  const authService = inject(AuthService);
  const router = inject(Router);

  authService.ensureBootstrap();

  return combineLatest([authService.session$, authService.isBootstrapped$]).pipe(
    filter(([, bootstrapped]) => bootstrapped),
    take(1),
    map(([session]) => (session ? true : router.createUrlTree(['/login']))),
  );
};
