import { Routes } from '@angular/router';
import { LoginComponent } from '@shared/auth/login/login.component';
import { lighthouseGuard } from '@shared/auth/lighthouse.guard';
import { AdminDashboardComponent } from '@shared/admin-dashboard/admin-dashboard.component';

export const appRoutes: Routes = [
  {
    path: '',
    pathMatch: 'full',
    redirectTo: 'dashboard',
  },
  {
    path: 'login',
    component: LoginComponent,
  },
  {
    path: 'dashboard',
    canActivate: [lighthouseGuard],
    children: [
      {
        path: '',
        pathMatch: 'full',
        redirectTo: 'companies',
      },
      {
        path: 'companies',
        component: AdminDashboardComponent,
      },
    ],
  },
  {
    path: '**',
    redirectTo: 'dashboard',
  },
];

