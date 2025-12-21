import { CommonModule } from '@angular/common';
import { Component, inject } from '@angular/core';
import { BillingService } from './billing.service';

@Component({
  selector: 'app-billing',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './billing.component.html',
})
export class BillingComponent {
  private readonly billingService = inject(BillingService);

  isLoading = false;
  errorMessage = '';

  manageBilling(): void {
    if (this.isLoading) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    this.billingService.createPortalSession().subscribe({
      next: (response) => {
        this.isLoading = false;
        if (response.url) {
          window.location.href = response.url;
          return;
        }
        this.errorMessage = 'Unable to open billing right now. Please try again.';
      },
      error: () => {
        this.isLoading = false;
        this.errorMessage = 'Unable to open billing right now. Please try again.';
      },
    });
  }
}
