import { Routes } from '@angular/router';
import { LandingComponent } from './landing/landing.component';
import { EarlyAccessComponent } from './auth/early-access.component';
import { LoginComponent } from './auth/login.component';
import { authGuard } from './auth/auth.guard';
import { DashboardComponent } from './dashboard/dashboard.component';
import { DashboardHomeComponent } from './dashboard/dashboard-home.component';
import { DashboardUsersComponent } from './dashboard/dashboard-users.component';
import { DashboardRunsComponent } from './dashboard/dashboard-runs.component';

export const routes: Routes = [
  { path: '', component: LandingComponent, pathMatch: 'full' },
  { path: 'early-access', component: EarlyAccessComponent },
  { path: 'login', component: LoginComponent },
  {
    path: 'dashboard',
    component: DashboardComponent,
    canActivate: [authGuard],
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'home' },
      { path: 'home', component: DashboardHomeComponent },
      { path: 'users', component: DashboardUsersComponent },
      { path: 'runs', component: DashboardRunsComponent },
    ],
  },
  { path: '**', redirectTo: '' },
];
