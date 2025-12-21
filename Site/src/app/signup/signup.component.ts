import { CommonModule } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnDestroy, inject } from '@angular/core';
import { NonNullableFormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { Subject, finalize, takeUntil } from 'rxjs';
import { AuthService, RegisterPayload } from '../auth/auth.service';
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
    tierId: ['tier-business', [Validators.required]],
    userFirstName: ['', [Validators.required]],
    userLastName: ['', [Validators.required]],
    userEmail: ['', [Validators.required, Validators.email]],
    userPassword: ['', [Validators.required, Validators.minLength(8)]],
    userPhone: ['', [Validators.required]],
  });

  readonly planOptions = [
    {
      id: 'tier-individual',
      name: 'Individual',
      price: '$60',
      description: '1 user account',
    },
    {
      id: 'tier-business',
      name: 'Business',
      price: '$100',
      description: '1 owner, 1 admin, 2 pickers/drivers',
    },
    {
      id: 'tier-enterprise-10',
      name: 'Enterprise 10',
      price: '$200',
      description: '1 owner, 1 admin, 10 pickers/drivers',
    },
  ];

  errorMessage = '';
  isSubmitting = false;
  step: 'details' | 'plan' = 'details';

  private readonly destroy$ = new Subject<void>();

  constructor(
    private readonly authService: AuthService,
    private readonly router: Router,
    private readonly billingService: BillingService,
  ) {
    this.authService.ensureBootstrap();
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
    if (this.step === 'details') {
      this.submitDetails();
      return;
    }

    this.submitPlan();
  }

  private submitDetails(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.isSubmitting = true;
    this.errorMessage = '';

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
          this.isSubmitting = false;
          this.step = 'plan';
        },
        error: (error: HttpErrorResponse) => {
          this.isSubmitting = false;
          this.errorMessage =
            error.error?.error ?? 'Unable to create your account right now. Please try again.';
        },
      });
  }

  private submitPlan(): void {
    if (this.form.get('tierId')?.invalid) {
      this.form.get('tierId')?.markAsTouched();
      return;
    }

    this.isSubmitting = true;
    this.errorMessage = '';

    const tierId = this.form.getRawValue().tierId;

    this.billingService
      .createCheckoutSession(tierId)
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
          this.errorMessage = 'Unable to start billing checkout right now. Please try again.';
        },
        error: (error: HttpErrorResponse) => {
          this.errorMessage =
            error.error?.error ?? 'Unable to start billing checkout right now. Please try again.';
        },
      });
  }
}
