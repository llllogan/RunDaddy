import { Routes } from '@angular/router';
import { LoginComponent } from './login/login.component';
import { DashboardComponent } from './dashboard/dashboard.component';
import { authGuard } from './auth/auth.guard';
import { PeopleComponent } from './people/people.component';
import { SignupComponent } from './signup/signup.component';
import { BillingComponent } from './billing/billing.component';

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
    path: 'signup',
    component: SignupComponent,
  },
  {
    path: 'dashboard',
    canActivate: [authGuard],
    children: [
      {
        path: '',
        pathMatch: 'full',
        redirectTo: 'runs',
      },
      {
        path: 'runs',
        component: DashboardComponent,
      },
      {
        path: 'people',
        component: PeopleComponent,
      },
      {
        path: 'billing',
        component: BillingComponent,
      },
    ],
  },
  {
    path: '**',
    redirectTo: 'dashboard',
  },
];
