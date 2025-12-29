import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { BillingService } from './billing.service';
import { planTiers } from './plan-tiers';

@Component({
  selector: 'app-billing',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './billing.component.html',
})
export class BillingComponent implements OnInit {
  private readonly billingService = inject(BillingService);
  private readonly cdr = inject(ChangeDetectorRef);

  readonly planOptions = planTiers;

  billingStatus = '';
  currentPeriodEnd: Date | null = null;
  currentTierId = '';

  isLoading = false;
  isStatusLoading = false;
  errorMessage = '';

  ngOnInit(): void {
    this.loadStatus();
  }

  manageBilling(): void {
    if (this.isLoading) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    this.cdr.detectChanges();

    this.billingService.createPortalSession().subscribe({
      next: (response) => {
        this.isLoading = false;
        this.cdr.detectChanges();
        if (response.url) {
          window.location.href = response.url;
          return;
        }
        this.errorMessage = 'Unable to open billing right now. Please try again.';
        this.cdr.detectChanges();
      },
      error: () => {
        this.isLoading = false;
        this.errorMessage = 'Unable to open billing right now. Please try again.';
        this.cdr.detectChanges();
      },
    });
  }

  isCurrentTier(tierId: string): boolean {
    return this.currentTierId === tierId;
  }

  getTierName(tierId: string): string {
    return this.planOptions.find((plan) => plan.id === tierId)?.name ?? 'Plan';
  }

  getStatusLabel(): string {
    switch (this.billingStatus) {
      case 'ACTIVE':
        return 'Active';
      case 'TRIALING':
        return 'Trialing';
      case 'PAST_DUE':
        return 'Past due';
      case 'UNPAID':
        return 'Unpaid';
      case 'INCOMPLETE':
        return 'Incomplete';
      case 'CANCELED':
        return 'Canceled';
      default:
        return 'Unknown';
    }
  }

  private loadStatus(): void {
    this.isStatusLoading = true;
    this.cdr.detectChanges();
    this.billingService.getStatus().subscribe({
      next: (status) => {
        this.billingStatus = status.billingStatus;
        this.currentTierId = status.tierId;
        this.currentPeriodEnd = status.currentPeriodEnd ? new Date(status.currentPeriodEnd) : null;
        this.isStatusLoading = false;
        this.cdr.detectChanges();
      },
      error: () => {
        this.isStatusLoading = false;
        this.cdr.detectChanges();
      },
    });
  }
}
