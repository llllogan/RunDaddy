import { Routes } from '@angular/router';
import { LandingComponent } from './landing/landing.component';
import { DashboardComponent } from './dashboard/dashboard.component';
import { EarlyAccessComponent } from './auth/early-access.component';
import { LoginComponent } from './auth/login.component';
import { authGuard } from './auth/auth.guard';

export const routes: Routes = [
  { path: '', component: LandingComponent, pathMatch: 'full' },
  { path: 'early-access', component: EarlyAccessComponent },
  { path: 'login', component: LoginComponent },
  { path: 'dashboard', component: DashboardComponent, canActivate: [authGuard] },
  { path: '**', redirectTo: '' },
];
