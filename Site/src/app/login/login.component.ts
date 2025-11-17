import { CommonModule } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnDestroy, inject } from '@angular/core';
import { NonNullableFormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { Subject, filter, finalize, takeUntil } from 'rxjs';
import { AuthService, AuthSession, LoginPayload, UserRole } from '../auth/auth.service';

interface MembershipChoice {
  companyId: string;
  companyName: string;
  role: UserRole;
}

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, RouterModule],
  templateUrl: './login.component.html',
})
export class LoginComponent implements OnDestroy {
  private readonly fb = inject(NonNullableFormBuilder);

  readonly form = this.fb.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required]],
  });

  errorMessage = '';
  membershipChoices: MembershipChoice[] = [];
  isSubmitting = false;

  private readonly destroy$ = new Subject<void>();

  constructor(
    private readonly authService: AuthService,
    private readonly router: Router,
  ) {
    this.authService.ensureBootstrap();

    this.authService.session$
      .pipe(
        takeUntil(this.destroy$),
        filter((session): session is AuthSession => Boolean(session)),
      )
      .subscribe(() => {
        void this.router.navigate(['/dashboard']);
      });
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  submit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.executeLogin();
  }

  selectCompany(companyId: string): void {
    this.executeLogin(companyId);
  }

  private executeLogin(companyId?: string): void {
    this.isSubmitting = true;
    this.errorMessage = '';

    const { email, password } = this.form.getRawValue();
    const payload: LoginPayload = {
      email,
      password,
      companyId,
      setAsDefault: true,
    };

    this.authService
      .login(payload)
      .pipe(
        finalize(() => {
          this.isSubmitting = false;
        }),
        takeUntil(this.destroy$),
      )
      .subscribe({
        next: () => {
          this.membershipChoices = [];
          void this.router.navigate(['/dashboard']);
        },
        error: (error: HttpErrorResponse) => {
          this.handleLoginError(error);
        },
      });
  }

  private handleLoginError(error: HttpErrorResponse): void {
    if (error.status === 401) {
      this.errorMessage = 'Invalid email or password.';
      return;
    }

    if (error.status === 412 && Array.isArray(error.error?.memberships)) {
      this.membershipChoices = error.error.memberships as MembershipChoice[];
      this.errorMessage = 'Choose which company dashboard to open.';
      return;
    }

    if (error.status === 404) {
      this.errorMessage = 'We could not find a company for that account.';
      return;
    }

    this.errorMessage = error.error?.error ?? 'Unable to sign in right now. Please try again.';
  }
}
