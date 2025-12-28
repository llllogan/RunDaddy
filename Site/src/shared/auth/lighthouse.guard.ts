import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { combineLatest, filter, map, take } from 'rxjs';
import { AuthService, AuthSession } from '@shared/auth/auth.service';

const isLighthouseSession = (session: AuthSession | null): boolean => {
  if (!session) {
    return false;
  }

  if (session.user.accountRole === 'LIGHTHOUSE' || session.user.lighthouse) {
    return true;
  }

  const platformAdminCompanyId = session.platformAdminCompanyId ?? null;
  const currentCompanyId = session.company?.id ?? null;

  return session.user.role === 'GOD' && Boolean(platformAdminCompanyId) && platformAdminCompanyId === currentCompanyId;
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
