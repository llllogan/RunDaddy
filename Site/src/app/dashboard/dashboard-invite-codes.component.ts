import { Component, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { InviteCodesService, InviteCode, CreateInviteCodeRequest } from './invite-codes.service';
import { AuthService } from '../auth/auth.service';

@Component({
  selector: 'app-dashboard-invite-codes',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './dashboard-invite-codes.component.html',
})
export class DashboardInviteCodesComponent {
  private readonly inviteCodesService = inject(InviteCodesService);
  private readonly authService = inject(AuthService);

  protected readonly inviteCodes = signal<InviteCode[]>([]);
  protected readonly loading = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly generating = signal(false);
  protected readonly selectedRole = signal<'ADMIN' | 'OWNER' | 'PICKER'>('PICKER');
  protected readonly showGenerateForm = signal(false);

  protected readonly user = this.authService.user;
  protected readonly company = this.authService.company;

  protected readonly canGenerateInvites = computed(() => {
    const userRole = this.user()?.role;
    return userRole === 'ADMIN' || userRole === 'OWNER';
  });

  protected readonly activeInviteCodes = computed(() => {
    return this.inviteCodes().filter(code => 
      !code.usedBy && new Date(code.expiresAt) > new Date()
    );
  });

  protected readonly usedInviteCodes = computed(() => {
    return this.inviteCodes().filter(code => code.usedBy);
  });

  protected readonly expiredInviteCodes = computed(() => {
    return this.inviteCodes().filter(code => 
      !code.usedBy && new Date(code.expiresAt) <= new Date()
    );
  });

  constructor() {
    this.loadInviteCodes();
  }

  protected loadInviteCodes(): void {
    const companyId = this.company()?.id;
    if (!companyId) {
      this.error.set('No company selected');
      return;
    }

    this.loading.set(true);
    this.error.set(null);

    this.inviteCodesService.getInviteCodes(companyId).subscribe({
      next: (codes) => {
        this.inviteCodes.set(codes);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err.message);
        this.loading.set(false);
      }
    });
  }

  protected generateInviteCode(): void {
    const companyId = this.company()?.id;
    if (!companyId) {
      this.error.set('No company selected');
      return;
    }

    const request: CreateInviteCodeRequest = {
      companyId,
      role: this.selectedRole()
    };

    this.generating.set(true);
    this.error.set(null);

    this.inviteCodesService.generateInviteCode(request).subscribe({
      next: (newCode) => {
        this.inviteCodes.update(codes => [newCode, ...codes]);
        this.generating.set(false);
        this.showGenerateForm.set(false);
        this.selectedRole.set('PICKER');
      },
      error: (err) => {
        this.error.set(err.message);
        this.generating.set(false);
      }
    });
  }

  protected copyToClipboard(code: string): void {
    navigator.clipboard.writeText(code).then(() => {
      // Could add a toast notification here
      console.log('Invite code copied to clipboard');
    }).catch(err => {
      console.error('Failed to copy code: ', err);
    });
  }

  protected formatDate(dateString: string): string {
    return new Date(dateString).toLocaleString();
  }

  protected isExpired(dateString: string): boolean {
    return new Date(dateString) <= new Date();
  }

  protected getRoleDisplay(role: string): string {
    return role.charAt(0) + role.slice(1).toLowerCase();
  }

  protected getCreatorName(creator?: { firstName?: string; lastName?: string }): string {
    if (!creator) return 'Unknown';
    if (creator.firstName && creator.lastName) {
      return `${creator.firstName} ${creator.lastName}`;
    }
    return creator.firstName || creator.lastName || 'Unknown';
  }

  protected getUsedByName(usedByUser?: { firstName?: string; lastName?: string }): string {
    if (!usedByUser) return 'Unknown';
    if (usedByUser.firstName && usedByUser.lastName) {
      return `${usedByUser.firstName} ${usedByUser.lastName}`;
    }
    return usedByUser.firstName || usedByUser.lastName || 'Unknown';
  }
}