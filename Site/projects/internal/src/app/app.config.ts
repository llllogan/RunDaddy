import { ApplicationConfig, provideBrowserGlobalErrorListeners, provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideAnimations } from '@angular/platform-browser/animations';
import { appRoutes } from './app.routes';
import { authInterceptor, credentialsInterceptor } from '@shared/auth/auth.interceptor';
import { provideShellConfig } from '@shared/layout/shell-config';
import { provideLoginConfig } from '@shared/auth/login/login-config';
import { provideAdminDashboardApiConfig } from '@shared/admin-dashboard/admin-dashboard-api-config';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideZonelessChangeDetection(),
    provideAnimations(),
    provideRouter(appRoutes),
    provideHttpClient(withInterceptors([credentialsInterceptor, authInterceptor])),
    provideAdminDashboardApiConfig({ basePath: '/lighthouse', allowDelete: false }),
    provideShellConfig({
      tabs: [{ id: 'companies', label: 'Companies', route: '/dashboard/companies' }],
      authRoutePrefixes: ['/login'],
    }),
    provideLoginConfig({
      postLoginRedirect: '/dashboard',
      allowSignup: false,
      signupRoute: '/login',
    }),
  ],
};
