import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { combineLatest, filter, map, take } from 'rxjs';
import { AuthService, AuthSession } from '@shared/auth/auth.service';

const isLighthouseSession = (session: AuthSession | null): boolean => {
  if (!session) {
    return false;
  }

  return session.user.accountRole === 'LIGHTHOUSE' || session.user.lighthouse === true;
};

export const lighthouseGuard: CanActivateFn = () => {
  const authService = inject(AuthService);
  const router = inject(Router);

  authService.ensureBootstrap();

  return combineLatest([authService.session$, authService.isBootstrapped$]).pipe(
    filter(([, bootstrapped]) => bootstrapped),
    take(1),
    map(([session]) => (isLighthouseSession(session) ? true : router.createUrlTree(['/login']))),
  );
};
