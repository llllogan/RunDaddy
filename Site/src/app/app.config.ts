import { ApplicationConfig, provideBrowserGlobalErrorListeners, provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideAnimations } from '@angular/platform-browser/animations';
import { appRoutes } from './app.routes';
import { authInterceptor, credentialsInterceptor } from './auth/auth.interceptor';
import { provideShellConfig } from '@shared/layout/shell-config';
import { provideLoginConfig } from '@shared/auth/login/login-config';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideZonelessChangeDetection(),
    provideAnimations(),
    provideRouter(appRoutes),
    provideHttpClient(withInterceptors([credentialsInterceptor, authInterceptor])),
    provideShellConfig({
      tabs: [
        { id: 'runs', label: 'Runs', route: '/dashboard/runs' },
        { id: 'people', label: 'People', route: '/dashboard/people' },
        { id: 'billing', label: 'Billing', route: '/dashboard/billing' },
      ],
      authRoutePrefixes: ['/login', '/signup'],
    }),
    provideLoginConfig({
      postLoginRedirect: '/dashboard',
      allowSignup: true,
      signupRoute: '/signup',
    }),
  ],
};
