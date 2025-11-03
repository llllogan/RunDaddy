import { Component, computed, effect, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { formatDate } from '@angular/common';
import { UsersService, DashboardUser } from './users.service';
import { AuthService } from '../auth/auth.service';

@Component({
  selector: 'app-dashboard-users',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard-users.component.html',
})
export class DashboardUsersComponent {
  private readonly usersService = inject(UsersService);
  private readonly auth = inject(AuthService);
  private lastUsersCompanyId: string | null = null;

  protected readonly users = signal<DashboardUser[]>([]);
  protected readonly loadingUsers = signal(false);
  protected readonly usersError = signal<string | null>(null);

  protected readonly hasUsers = computed(() => this.users().length > 0);
  protected readonly company = this.auth.company;

  constructor() {
    effect(() => {
      const companyId = this.company()?.id ?? null;
      if (!companyId) {
        this.users.set([]);
        this.lastUsersCompanyId = null;
        return;
      }
      void this.loadUsers(companyId);
    });
  }

  protected reloadUsers(): void {
    if (this.loadingUsers()) {
      return;
    }

    const companyId = this.company()?.id;
    if (!companyId) {
      return;
    }
    void this.loadUsers(companyId, true);
  }

  protected trackByUser = (_: number, user: DashboardUser): string => user.id;

  protected formatUserName(user: DashboardUser): string {
    const parts = [user.firstName, user.lastName].filter(Boolean);
    return parts.length ? parts.join(' ') : user.email;
  }

  protected formatRole(role: string | null | undefined): string {
    return this.formatStatus(role);
  }

  protected formatDateTime(value: Date | null | undefined, format: string = 'MMM d, h:mm a'): string {
    if (!value) {
      return '—';
    }
    const timestamp = value instanceof Date ? value.getTime() : new Date(value).getTime();
    if (Number.isNaN(timestamp)) {
      return '—';
    }
    return formatDate(timestamp, format, 'en-US');
  }

  private formatStatus(status: string | null | undefined): string {
    if (!status) {
      return 'Unknown';
    }
    return status
      .toLowerCase()
      .split('_')
      .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
      .join(' ');
  }

  private async loadUsers(companyId: string, force = false): Promise<void> {
    if (!force && companyId === this.lastUsersCompanyId) {
      return;
    }

    this.loadingUsers.set(true);
    this.usersError.set(null);

    try {
      const list = await this.usersService.listUsers();
      this.users.set(list);
      this.lastUsersCompanyId = companyId;
    } catch (error) {
      this.usersError.set(error instanceof Error ? error.message : 'Unable to load users.');
      if (!force) {
        this.lastUsersCompanyId = null;
      }
    } finally {
      this.loadingUsers.set(false);
    }
  }
}
