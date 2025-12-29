import { provideZonelessChangeDetection } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { App } from './app';
import { AuthService } from './auth/auth.service';
import { provideShellConfig } from '@shared/layout/shell-config';
import { provideLoginConfig } from '@shared/auth/login/login-config';

class AuthServiceStub {
  session$ = of({
    user: {
      id: 'user-1',
      email: 'admin@example.com',
      firstName: 'Admin',
      lastName: 'User',
      role: 'OWNER',
    },
    company: null,
  });
  isBootstrapped$ = of(true);
  ensureBootstrap = jasmine.createSpy('ensureBootstrap');
  logout = jasmine.createSpy('logout').and.returnValue(of(void 0));
}

describe('App', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [
        provideZonelessChangeDetection(),
        provideRouter([]),
        { provide: AuthService, useClass: AuthServiceStub },
        provideShellConfig({
          tabs: [],
          authRoutePrefixes: ['/login', '/signup'],
        }),
        provideLoginConfig({
          postLoginRedirect: '/dashboard',
          allowSignup: true,
          signupRoute: '/signup',
        }),
      ],
    }).compileComponents();
  });

  it('should create the app', () => {
    const fixture = TestBed.createComponent(App);
    const app = fixture.componentInstance;
    expect(app).toBeTruthy();
  });

  it('should render the Picker Agent sidebar', () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.textContent).toContain('Picker Agent');
    expect(compiled.textContent).toContain('Dashboard');
  });
});
