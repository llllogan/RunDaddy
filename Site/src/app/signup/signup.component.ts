import { CommonModule } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnDestroy, inject } from '@angular/core';
import { NonNullableFormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { Subject, filter, finalize, takeUntil } from 'rxjs';
import { AuthService, AuthSession, RegisterPayload } from '../auth/auth.service';
import { BillingService } from '../billing/billing.service';

@Component({
  selector: 'app-signup',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, RouterModule],
  templateUrl: './signup.component.html',
})
export class SignupComponent implements OnDestroy {
  private readonly fb = inject(NonNullableFormBuilder);

  readonly form = this.fb.group({
    companyName: ['', [Validators.required, Validators.minLength(2)]],
    userFirstName: ['', [Validators.required]],
    userLastName: ['', [Validators.required]],
    userEmail: ['', [Validators.required, Validators.email]],
    userPassword: ['', [Validators.required, Validators.minLength(8)]],
    userPhone: ['', [Validators.required]],
  });

  errorMessage = '';
  isSubmitting = false;
  private allowAutoRedirect = true;

  private readonly destroy$ = new Subject<void>();

  constructor(
    private readonly authService: AuthService,
    private readonly router: Router,
    private readonly billingService: BillingService,
  ) {
    this.authService.ensureBootstrap();

    this.authService.session$
      .pipe(
        takeUntil(this.destroy$),
        filter((session): session is AuthSession => Boolean(session)),
      )
      .subscribe(() => {
        if (!this.allowAutoRedirect) {
          return;
        }
        void this.router.navigate(['/dashboard']);
      });
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  get requiresPhoneCode(): boolean {
    const phone = this.form.get('userPhone')?.value?.trim();
    return phone !== '5555555555';
  }

  submit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.isSubmitting = true;
    this.errorMessage = '';
    this.allowAutoRedirect = false;

    const { companyName, userFirstName, userLastName, userEmail, userPassword, userPhone } =
      this.form.getRawValue();

    const payload: RegisterPayload = {
      companyName: companyName.trim(),
      userFirstName: userFirstName.trim(),
      userLastName: userLastName.trim(),
      userEmail: userEmail.trim(),
      userPassword,
      userPhone: userPhone.trim(),
    };

    this.authService
      .registerCompanyAccount(payload)
      .pipe(
        takeUntil(this.destroy$),
      )
      .subscribe({
        next: () => {
          this.billingService
            .createCheckoutSession()
            .pipe(
              finalize(() => {
                this.isSubmitting = false;
              }),
              takeUntil(this.destroy$),
            )
            .subscribe({
              next: (response) => {
                if (response.url) {
                  window.location.href = response.url;
                  return;
                }
                this.errorMessage =
                  'Unable to start billing checkout right now. Please try again.';
              },
              error: (error: HttpErrorResponse) => {
                this.errorMessage =
                  error.error?.error ??
                  'Unable to start billing checkout right now. Please try again.';
              },
            });
        },
        error: (error: HttpErrorResponse) => {
          this.isSubmitting = false;
          this.allowAutoRedirect = true;
          this.errorMessage =
            error.error?.error ?? 'Unable to create your account right now. Please try again.';
        },
      });
  }
}
