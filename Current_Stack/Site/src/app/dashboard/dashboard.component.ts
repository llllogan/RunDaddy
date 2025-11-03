import { Component, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { AuthService, MembershipChoice } from '../auth/auth.service';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './dashboard.component.html',
})
export class DashboardComponent {
  private readonly auth = inject(AuthService);

  protected readonly tabs = [
    { id: 'home', label: 'Home', route: 'home' },
    { id: 'users', label: 'Users', route: 'users' },
    { id: 'runs', label: 'Runs', route: 'runs' },
  ] as const;

  protected readonly memberships = signal<MembershipChoice[]>([]);
  protected readonly loadingMemberships = signal(false);
  protected readonly isSwitchingCompany = signal(false);
  protected readonly companySwitchError = signal<string | null>(null);
  protected readonly companyModalOpen = signal(false);

  protected readonly user = this.auth.user;
  protected readonly company = this.auth.company;
  protected readonly showCompanySelector = computed(
    () => this.loadingMemberships() || this.memberships().length > 1 || !!this.companySwitchError(),
  );

  constructor() {
    void this.loadMemberships();
  }

  protected async logout(): Promise<void> {
    await this.auth.logout();
  }

  protected openCompanyModal(): void {
    if (this.isSwitchingCompany()) {
      return;
    }
    this.companyModalOpen.set(true);
  }

  protected closeCompanyModal(): void {
    if (this.isSwitchingCompany()) {
      return;
    }
    this.companyModalOpen.set(false);
  }

  protected async selectCompany(targetCompanyId: string): Promise<void> {
    const currentCompanyId = this.company()?.id ?? '';

    if (!targetCompanyId || targetCompanyId === currentCompanyId) {
      this.closeCompanyModal();
      return;
    }

    this.isSwitchingCompany.set(true);
    this.companySwitchError.set(null);

    try {
      await this.auth.switchCompany(targetCompanyId);
      this.closeCompanyModal();
    } catch (error) {
      this.companySwitchError.set(error instanceof Error ? error.message : 'Unable to switch company.');
    } finally {
      this.isSwitchingCompany.set(false);
    }
  }

  protected reloadMemberships(): void {
    if (this.loadingMemberships()) {
      return;
    }
    void this.loadMemberships();
  }

  private async loadMemberships(): Promise<void> {
    this.loadingMemberships.set(true);
    this.companySwitchError.set(null);

    try {
      const memberships = await this.auth.listMemberships();
      this.memberships.set(memberships);
    } catch (error) {
      this.companySwitchError.set(error instanceof Error ? error.message : 'Unable to load companies.');
    } finally {
      this.loadingMemberships.set(false);
    }
  }
}
