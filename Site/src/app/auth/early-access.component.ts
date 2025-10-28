import { CommonModule } from '@angular/common';
import { Component, inject, signal } from '@angular/core';
import { ReactiveFormsModule, Validators, FormBuilder } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService, RegisterInput } from './auth.service';

@Component({
  selector: 'app-early-access',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, RouterLink],
  templateUrl: './early-access.component.html',
})
export class EarlyAccessComponent {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly submitting = signal(false);
  protected readonly error = signal<string | null>(null);

  protected readonly form = this.fb.group({
    companyName: ['', [Validators.required, Validators.minLength(2)]],
    companyDescription: [''],
    adminFirstName: ['', [Validators.required, Validators.minLength(1)]],
    adminLastName: ['', [Validators.required, Validators.minLength(1)]],
    adminEmail: ['', [Validators.required, Validators.email]],
    adminPassword: ['', [Validators.required, Validators.minLength(8)]],
    adminPhone: [''],
  });

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
    if (control.errors['minlength']) {
      const required = control.errors['minlength'].requiredLength;
      return `Minimum length is ${required} characters.`;
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
      const payload = this.form.getRawValue() as RegisterInput;
      await this.auth.register(payload);
      await this.router.navigate(['/dashboard']);
    } catch (error) {
      this.error.set(error instanceof Error ? error.message : 'Unable to complete registration.');
    } finally {
      this.submitting.set(false);
    }
  }
}
