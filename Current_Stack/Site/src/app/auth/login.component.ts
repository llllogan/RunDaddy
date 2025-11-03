import { CommonModule } from '@angular/common';
import { Component, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ReactiveFormsModule, Validators, FormBuilder } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { AuthService, CompanySelectionRequiredError, LoginInput, MembershipChoice } from './auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, RouterLink],
  templateUrl: './login.component.html',
})
export class LoginComponent {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  protected readonly submitting = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly memberships = signal<MembershipChoice[]>([]);

  protected readonly form = this.fb.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required]],
    companyId: [''],
    setAsDefault: [true],
  });

  constructor() {
    const emailControl = this.form.get('email');
    emailControl?.valueChanges.pipe(takeUntilDestroyed()).subscribe(() => {
      if (!this.memberships().length || !emailControl.dirty) {
        return;
      }
      this.clearCompanySelection();
    });
  }

  protected shouldShowError(controlName: string): boolean {
    const control = this.form.get(controlName);
    return !!control && control.invalid && (control.dirty || control.touched);
  }

  protected getErrorMessage(controlName: string): string {
    const control = this.form.get(controlName);
    if (!control || !control.errors) {
      return '';
    }

    if (control.errors['required']) {
      return 'This field is required.';
    }
    if (control.errors['email']) {
      return 'Enter a valid email address.';
    }
    return 'Please enter a valid value.';
  }

  protected async submit(): Promise<void> {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.submitting.set(true);
    this.error.set(null);

    try {
      const raw = this.form.getRawValue();
      const payload: LoginInput = {
        email: raw.email?.trim() ?? '',
        password: raw.password ?? '',
      };

      const companyId = typeof raw.companyId === 'string' ? raw.companyId.trim() : '';
      if (companyId) {
        payload.companyId = companyId;
        payload.setAsDefault = raw.setAsDefault ?? true;
      }

      await this.auth.login(payload);
      this.clearCompanySelection();
      const returnUrl = this.route.snapshot.queryParamMap.get('returnUrl') ?? '/dashboard';
      await this.router.navigateByUrl(returnUrl);
    } catch (error) {
      if (error instanceof CompanySelectionRequiredError) {
        this.enableCompanySelection(error.memberships);
        this.error.set(error.message);
      } else {
        this.error.set(error instanceof Error ? error.message : 'Unable to sign in.');
      }
    } finally {
      this.submitting.set(false);
    }
  }

  protected formatRole(role: string): string {
    return role
      .toLowerCase()
      .split('_')
      .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
      .join(' ');
  }

  private enableCompanySelection(memberships: MembershipChoice[]): void {
    if (!memberships.length) {
      return;
    }

    const companyControl = this.form.get('companyId');
    if (!companyControl) {
      return;
    }

    const sorted = [...memberships].sort((a, b) => a.companyName.localeCompare(b.companyName));
    this.memberships.set(sorted);
    companyControl.setValidators([Validators.required]);
    companyControl.setValue('', { emitEvent: false });
    companyControl.markAsPristine();
    companyControl.markAsUntouched();
    companyControl.updateValueAndValidity({ emitEvent: false });

    const defaultControl = this.form.get('setAsDefault');
    defaultControl?.setValue(true, { emitEvent: false });
  }

  private clearCompanySelection(): void {
    if (!this.memberships().length) {
      return;
    }

    const companyControl = this.form.get('companyId');
    if (companyControl) {
      companyControl.clearValidators();
      companyControl.setValue('', { emitEvent: false });
      companyControl.markAsPristine();
      companyControl.markAsUntouched();
      companyControl.updateValueAndValidity({ emitEvent: false });
    }

    this.form.get('setAsDefault')?.setValue(true, { emitEvent: false });
    this.memberships.set([]);
    this.error.set(null);
  }
}
