import { InjectionToken, Provider } from '@angular/core';

export type ShellTabId = string;

export interface ShellTab {
  id: ShellTabId;
  label: string;
  route: string;
  requiresAdminContext?: boolean;
}

export interface ShellConfig {
  tabs: ReadonlyArray<ShellTab>;
  authRoutePrefixes: ReadonlyArray<string>;
}

export const SHELL_CONFIG = new InjectionToken<ShellConfig>('SHELL_CONFIG');

export const provideShellConfig = (config: ShellConfig): Provider => ({
  provide: SHELL_CONFIG,
  useValue: config,
});

