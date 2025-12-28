import { InjectionToken, Provider } from '@angular/core';

export interface LoginConfig {
  postLoginRedirect: string;
  allowSignup: boolean;
  signupRoute: string;
}

export const LOGIN_CONFIG = new InjectionToken<LoginConfig>('LOGIN_CONFIG');

export const provideLoginConfig = (config: LoginConfig): Provider => ({
  provide: LOGIN_CONFIG,
  useValue: config,
});

