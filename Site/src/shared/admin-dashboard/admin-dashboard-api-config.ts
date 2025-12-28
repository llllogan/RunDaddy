import { InjectionToken, Provider } from '@angular/core';

export interface AdminDashboardApiConfig {
  basePath: '/admin' | '/lighthouse';
  allowDelete: boolean;
}

export const ADMIN_DASHBOARD_API_CONFIG = new InjectionToken<AdminDashboardApiConfig>(
  'ADMIN_DASHBOARD_API_CONFIG',
);

export const provideAdminDashboardApiConfig = (config: AdminDashboardApiConfig): Provider => ({
  provide: ADMIN_DASHBOARD_API_CONFIG,
  useValue: config,
});

