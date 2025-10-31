import { Component, computed, effect, inject, signal } from '@angular/core';
import { CommonModule, formatDate } from '@angular/common';
import { RouterModule } from '@angular/router';
import { AuthService, MembershipChoice } from '../auth/auth.service';
import { RunsService, RunOverviewEntry, RunPerson } from './runs.service';
import { DashboardUser, UsersService } from './users.service';
import { RunImportsService } from './run-imports.service';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './dashboard.component.html',
})
export class DashboardComponent {
  private readonly auth = inject(AuthService);
  private readonly runsService = inject(RunsService);
  private readonly usersService = inject(UsersService);
  private readonly runImportsService = inject(RunImportsService);
  private lastRunsCompanyId: string | null = null;
  private lastUsersCompanyId: string | null = null;

  protected readonly tabs = [
    { id: 'home', label: 'Home' },
    { id: 'users', label: 'Users' },
    { id: 'runs', label: 'Runs' },
  ] as const;

  protected readonly activeTab = signal<'home' | 'users' | 'runs'>('home');
  protected readonly isDragging = signal(false);
  protected readonly memberships = signal<MembershipChoice[]>([]);
  protected readonly loadingMemberships = signal(false);
  protected readonly isSwitchingCompany = signal(false);
  protected readonly companySwitchError = signal<string | null>(null);
  protected readonly companyModalOpen = signal(false);
  protected readonly runs = signal<RunOverviewEntry[]>([]);
  protected readonly loadingRuns = signal(false);
  protected readonly runsError = signal<string | null>(null);
  protected readonly users = signal<DashboardUser[]>([]);
  protected readonly loadingUsers = signal(false);
  protected readonly usersError = signal<string | null>(null);
  protected readonly uploadingRun = signal(false);
  protected readonly uploadError = signal<string | null>(null);

  protected readonly hasRuns = computed(() => this.runs().length > 0);
  protected readonly hasUsers = computed(() => this.users().length > 0);
  protected readonly user = this.auth.user;
  protected readonly company = this.auth.company;
  protected readonly showCompanySelector = computed(
    () => this.loadingMemberships() || this.memberships().length > 1 || !!this.companySwitchError(),
  );

  constructor() {
    void this.loadMemberships();
    effect(() => {
      const companyId = this.company()?.id ?? null;
      if (!companyId) {
        return;
      }
      void this.loadRuns(companyId);
      void this.loadUsers(companyId);
    });
  }

  protected setTab(tab: 'home' | 'users' | 'runs'): void {
    this.activeTab.set(tab);
  }

  protected onDragOver(event: DragEvent): void {
    event.preventDefault();
    event.stopPropagation();
    if (!this.isDragging()) {
      this.isDragging.set(true);
    }
  }

  protected onDragLeave(event: DragEvent): void {
    event.preventDefault();
    event.stopPropagation();
    if (this.isDragging()) {
      this.isDragging.set(false);
    }
  }

  protected onDrop(event: DragEvent): void {
    event.preventDefault();
    event.stopPropagation();
    this.isDragging.set(false);
    if (!event.dataTransfer?.files?.length) {
      return;
    }
    this.handleFiles(event.dataTransfer.files);
  }

  protected onFileSelect(event: Event): void {
    const input = event.target as HTMLInputElement;
    if (!input.files?.length) {
      return;
    }
    this.handleFiles(input.files);
    input.value = '';
  }

  private handleFiles(fileList: FileList): void {
    const acceptedTypes = [
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-excel',
      'text/csv',
    ];
    const incoming = Array.from(fileList).filter(
      (file) => acceptedTypes.includes(file.type) || file.name.endsWith('.xlsx') || file.name.endsWith('.xls'),
    );
    if (!incoming.length) {
      return;
    }
    if (this.uploadingRun()) {
      return;
    }
    const [file] = incoming;
    if (!file) {
      return;
    }
    void this.processRunUpload(file);
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

  protected reloadRuns(): void {
    if (this.loadingRuns()) {
      return;
    }
    const companyId = this.company()?.id;
    if (!companyId) {
      return;
    }
    void this.loadRuns(companyId, true);
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

  protected formatStatus(status: string | null | undefined): string {
    if (!status) {
      return 'Unknown';
    }
    return status
      .toLowerCase()
      .split('_')
      .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
      .join(' ');
  }

  protected formatRole(role: string | null | undefined): string {
    return this.formatStatus(role);
  }

  protected statusBadgeClass(status: string): string {
    const mapping: Record<string, string> = {
      COMPLETED: 'border border-rd-teal/30 bg-rd-teal/10 text-rd-teal',
      READY: 'border border-rd-teal/30 bg-rd-teal/10 text-rd-teal',
      IN_PROGRESS: 'border border-rd-accent/30 bg-rd-accent/10 text-rd-accent',
      PICKING: 'border border-rd-accent/30 bg-rd-accent/10 text-rd-accent',
      SCHEDULED: 'border border-[#f9c74f]/30 bg-[#f9c74f]/10 text-[#b96f05]',
      DRAFT: 'border border-rd-primary/12 bg-white/75 text-rd-secondary',
      HISTORICAL: 'border border-rd-primary/12 bg-white/60 text-rd-secondary',
      CANCELLED: 'border border-[#f87171]/30 bg-[#f87171]/10 text-[#c24141]',
    };
    return mapping[status] ?? 'border border-rd-primary/12 bg-white/75 text-rd-secondary';
  }

  protected formatPerson(person: RunPerson | null): string {
    if (!person) {
      return '—';
    }
    const parts = [person.firstName, person.lastName].filter(Boolean);
    return parts.length ? parts.join(' ') : person.id;
  }

  protected trackByRun = (_: number, run: RunOverviewEntry): string => run.id;
  protected trackByUser = (_: number, user: DashboardUser): string => user.id;

  protected formatUserName(user: DashboardUser): string {
    const parts = [user.firstName, user.lastName].filter(Boolean);
    return parts.length ? parts.join(' ') : user.email;
  }

  protected getRunUpdatedAt(run: RunOverviewEntry): Date | null {
    return run.pickingEndedAt ?? run.pickingStartedAt ?? run.createdAt ?? null;
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

  private async loadRuns(companyId: string, force = false): Promise<void> {
    if (!force && companyId === this.lastRunsCompanyId) {
      return;
    }

    this.loadingRuns.set(true);
    this.runsError.set(null);

    try {
      const overview = await this.runsService.getOverview();
      this.runs.set(overview);
      this.lastRunsCompanyId = companyId;
    } catch (error) {
      this.runsError.set(error instanceof Error ? error.message : 'Unable to load runs.');
      if (!force) {
        this.lastRunsCompanyId = null;
      }
    } finally {
      this.loadingRuns.set(false);
    }
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

  private async processRunUpload(file: File): Promise<void> {
    if (this.uploadingRun()) {
      return;
    }
    this.uploadingRun.set(true);
    this.uploadError.set(null);
    try {
      await this.runImportsService.uploadRun(file);
      const companyId = this.company()?.id ?? null;
      if (companyId) {
        await this.loadRuns(companyId, true);
      }
      this.activeTab.set('runs');
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'Unable to process this workbook. Please try again.';
      this.uploadError.set(message);
    } finally {
      this.uploadingRun.set(false);
    }
  }
}
