import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { combineLatest, filter, map, take } from 'rxjs';
import { AuthService } from './auth.service';

export const adminGuard: CanActivateFn = () => {
  const authService = inject(AuthService);
  const router = inject(Router);

  authService.ensureBootstrap();

  return combineLatest([authService.session$, authService.isBootstrapped$]).pipe(
    filter(([, bootstrapped]) => bootstrapped),
    take(1),
    map(([session]) => {
      const isGod = session?.user?.role === 'GOD';
      const platformAdminCompanyId = session?.platformAdminCompanyId ?? null;
      const currentCompanyId = session?.company?.id ?? null;
      const isAdminContext =
        Boolean(platformAdminCompanyId) &&
        platformAdminCompanyId === currentCompanyId &&
        session?.user?.platformAdmin;

      return isGod || isAdminContext ? true : router.createUrlTree(['/dashboard']);
    }),
  );
};
