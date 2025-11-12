import { Routes } from '@angular/router';
import { LoginComponent } from './login/login.component';
import { DashboardComponent } from './dashboard/dashboard.component';
import { HomeComponent } from './home/home.component';
import { authGuard } from './auth/auth.guard';
import { SignupComponent } from './signup/signup.component';
import { PeopleComponent } from './people/people.component';

export const appRoutes: Routes = [
  {
    path: '',
    component: HomeComponent,
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
    ],
  },
  {
    path: '**',
    redirectTo: '',
  },
];
