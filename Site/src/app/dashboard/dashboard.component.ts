import { Component, computed, effect, inject, signal } from '@angular/core';
import { CommonModule, formatDate } from '@angular/common';
import { RouterModule } from '@angular/router';
import { AuthService, MembershipChoice } from '../auth/auth.service';
import { RunsService, RunOverviewEntry, RunPerson } from './runs.service';
import { DashboardUser, UsersService } from './users.service';
import { RunImportPreview, RunImportsService } from './run-imports.service';

type UploadStatus = 'uploading' | 'success' | 'error';

interface UploadedFile {
  id: string;
  file: File;
  receivedAt: Date;
  status: UploadStatus;
  result: RunImportPreview | null;
  error: string | null;
}

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
  protected readonly uploadedFiles = signal<UploadedFile[]>([]);
  protected readonly memberships = signal<MembershipChoice[]>([]);
  protected readonly loadingMemberships = signal(false);
  protected readonly isSwitchingCompany = signal(false);
  protected readonly companySwitchError = signal<string | null>(null);
  protected readonly runs = signal<RunOverviewEntry[]>([]);
  protected readonly loadingRuns = signal(false);
  protected readonly runsError = signal<string | null>(null);
  protected readonly users = signal<DashboardUser[]>([]);
  protected readonly loadingUsers = signal(false);
  protected readonly usersError = signal<string | null>(null);

  protected readonly hasFiles = computed(() => this.uploadedFiles().length > 0);
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

  protected removeFile(id: string): void {
    this.removeUpload(id);
  }

  protected formatFileSize(bytes: number): string {
    if (bytes === 0) {
      return '0 B';
    }
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    const size = bytes / Math.pow(k, i);
    return `${size.toFixed(size >= 10 || i === 0 ? 0 : 1)} ${sizes[i]}`;
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
    incoming.forEach((file) => this.queueFileForUpload(file));
  }

  protected retryUpload(id: string): void {
    const current = this.getUploadById(id);
    if (!current) {
      return;
    }
    this.updateUpload(id, (upload) => ({
      ...upload,
      status: 'uploading',
      error: null,
      result: null,
    }));
    void this.uploadWorkbook(id);
  }

  protected async logout(): Promise<void> {
    await this.auth.logout();
  }

  protected async onCompanyChange(event: Event): Promise<void> {
    const select = event.target as HTMLSelectElement;
    const targetCompanyId = select.value;
    const currentCompanyId = this.company()?.id ?? '';

    if (!targetCompanyId || targetCompanyId === currentCompanyId) {
      return;
    }

    this.isSwitchingCompany.set(true);
    this.companySwitchError.set(null);

    try {
      await this.auth.switchCompany(targetCompanyId);
    } catch (error) {
      this.companySwitchError.set(error instanceof Error ? error.message : 'Unable to switch company.');
      select.value = currentCompanyId;
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

  protected uploadStatusLabel(status: UploadStatus): string {
    switch (status) {
      case 'uploading':
        return 'Uploading...';
      case 'success':
        return 'Uploaded';
      case 'error':
        return 'Failed';
      default:
        return status;
    }
  }

  protected uploadStatusClass(status: UploadStatus): string {
    const mapping: Record<UploadStatus, string> = {
      uploading: 'border border-rd-primary/12 bg-white/80 text-rd-secondary',
      success: 'border border-rd-teal/30 bg-rd-teal/10 text-rd-teal',
      error: 'border border-[#f87171]/30 bg-[#f87171]/10 text-[#c24141]',
    };
    return mapping[status];
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

  private queueFileForUpload(file: File): void {
    const entry: UploadedFile = {
      id: this.createUploadId(),
      file,
      receivedAt: new Date(),
      status: 'uploading',
      result: null,
      error: null,
    };
    this.uploadedFiles.update((files) => [...files, entry]);
    void this.uploadWorkbook(entry.id);
  }

  private async uploadWorkbook(id: string): Promise<void> {
    const entry = this.getUploadById(id);
    if (!entry) {
      return;
    }

    try {
      const preview = await this.runImportsService.uploadRun(entry.file);
      this.updateUpload(id, (upload) => ({
        ...upload,
        status: 'success',
        error: null,
        result: preview,
      }));
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'Unable to process this workbook. Please try again.';
      this.updateUpload(id, (upload) => ({
        ...upload,
        status: 'error',
        error: message,
        result: null,
      }));
    }
  }

  private getUploadById(id: string): UploadedFile | undefined {
    return this.uploadedFiles().find((upload) => upload.id === id);
  }

  private updateUpload(id: string, mutate: (upload: UploadedFile) => UploadedFile): void {
    this.uploadedFiles.update((files) =>
      files.map((upload) => (upload.id === id ? mutate(upload) : upload)),
    );
  }

  private removeUpload(id: string): void {
    this.uploadedFiles.update((files) => files.filter((upload) => upload.id !== id));
  }

  private createUploadId(): string {
    if (typeof globalThis.crypto !== 'undefined' && 'randomUUID' in globalThis.crypto) {
      return globalThis.crypto.randomUUID();
    }
    return `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
  }
}
