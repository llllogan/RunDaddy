import { Component, computed, effect, inject, signal } from '@angular/core';
import { CommonModule, formatDate } from '@angular/common';
import { RunsService, RunOverviewEntry, RunAssignmentRole } from './runs.service';
import { AuthService } from '../auth/auth.service';
import { UsersService, DashboardUser } from './users.service';

@Component({
  selector: 'app-dashboard-runs',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard-runs.component.html',
})
export class DashboardRunsComponent {
  private readonly runsService = inject(RunsService);
  private readonly usersService = inject(UsersService);
  private readonly auth = inject(AuthService);
  private lastRunsCompanyId: string | null = null;

  protected readonly runs = signal<RunOverviewEntry[]>([]);
  protected readonly loadingRuns = signal(false);
  protected readonly runsError = signal<string | null>(null);
  protected readonly participantNames = signal<Record<string, string>>({});
  protected readonly loadingParticipantNames = signal(false);
  protected readonly assignmentContext = signal<
    { runId: string; run: RunOverviewEntry; role: RunAssignmentRole } | null
  >(null);
  protected readonly isAssigning = signal(false);
  protected readonly members = signal<DashboardUser[]>([]);
  protected readonly membersLoading = signal(false);
  protected readonly membersError = signal<string | null>(null);
  protected readonly assignmentError = signal<string | null>(null);

  protected readonly hasRuns = computed(() => this.runs().length > 0);
  protected readonly company = this.auth.company;

  constructor() {
    effect(() => {
      const companyId = this.company()?.id ?? null;
      if (!companyId) {
        this.runs.set([]);
        this.participantNames.set({});
        this.lastRunsCompanyId = null;
        return;
      }

      void this.loadRuns(companyId);
    });
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

  protected trackByRun = (index: number, run: RunOverviewEntry): string => this.resolveRunId(run) ?? `run-${index}`;

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

  protected formatDateTime(value: Date | null): string {
    if (!value) {
      return '—';
    }
    return formatDate(value, 'MMM d, y, h:mm a', 'en-US');
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
      await this.hydrateParticipantNames(overview);
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

  protected participantNameFor(userId: string | null, fallback?: string | null): string {
    if (!userId) {
      return '—';
    }
    const mapped = this.participantNames()[userId];
    if (mapped) {
      return mapped;
    }
    const safeFallback = (fallback ?? '').trim();
    return safeFallback || '—';
  }

  protected openAssignmentModal(run: RunOverviewEntry, role: RunAssignmentRole): void {
    if (this.isAssigning()) {
      return;
    }
    this.assignmentError.set(null);
    const resolvedRunId = this.resolveRunId(run);

    if (!resolvedRunId) {
      this.assignmentError.set('Unable to determine which run to update.');
      this.assignmentContext.set({ runId: '', run, role });
      return;
    }

    this.assignmentContext.set({ runId: resolvedRunId, run, role });

    const shouldLoadMembers = (!this.members().length && !this.membersLoading()) || !!this.membersError();
    if (shouldLoadMembers) {
      void this.loadMembers(this.membersError() !== null);
    }
  }

  protected closeAssignmentModal(): void {
    if (this.isAssigning()) {
      return;
    }
    this.assignmentError.set(null);
    this.assignmentContext.set(null);
  }

  protected reloadMembers(): void {
    if (this.membersLoading()) {
      return;
    }
    void this.loadMembers(true);
  }

  protected async assignToUser(runId: string | null, role: RunAssignmentRole | null, userId: string): Promise<void> {
    const context = this.assignmentContext();
    const effectiveRunId = runId ?? context?.runId ?? null;
    const effectiveRole = role ?? context?.role ?? null;

    if (!effectiveRunId || !effectiveRole) {
      this.assignmentError.set('Unable to determine which run to update.');
      return;
    }

    if (this.isAssigning()) {
      return;
    }

    this.isAssigning.set(true);
    this.assignmentError.set(null);

    try {
      const updated = await this.runsService.assignParticipant(effectiveRunId, userId, effectiveRole);
      this.runs.update((runs) => runs.map((run) => (run.id === updated.id ? updated : run)));
      this.applyParticipantNames([updated]);
      this.assignmentContext.set(null);
    } catch (error) {
      this.assignmentError.set(error instanceof Error ? error.message : 'Unable to assign run.');
    } finally {
      this.isAssigning.set(false);
    }
  }

  protected trackByMember = (_: number, member: DashboardUser): string => member.id;

  protected assignmentRoleLabel(role: RunAssignmentRole): string {
    return role === 'PICKER' ? 'picker' : 'runner';
  }

  protected assignmentRoleTitle(role: RunAssignmentRole): string {
    return role === 'PICKER' ? 'Assign picker' : 'Assign runner';
  }

  private resolveRunId(run: RunOverviewEntry): string | null {
    const candidate = this.normalizeRunId((run as { id?: unknown }).id);
    if (candidate) {
      return candidate;
    }

    const legacy = run as unknown as Record<string, unknown>;
    const fallbackKeys = ['runId', 'run_id', 'runID'];

    for (const key of fallbackKeys) {
      const value = this.normalizeRunId(legacy[key]);
      if (value) {
        return value;
      }
    }

    return null;
  }

  private normalizeRunId(value: unknown): string | null {
    if (typeof value === 'string') {
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : null;
    }

    if (typeof value === 'number' && Number.isFinite(value)) {
      return String(value);
    }

    if (value instanceof Uint8Array || value instanceof ArrayBuffer) {
      const buffer = value instanceof ArrayBuffer ? new Uint8Array(value) : value;
      return new TextDecoder().decode(buffer).trim() || null;
    }

    if (value && typeof value === 'object' && 'toString' in value) {
      const stringified = String(value).trim();
      return stringified.length > 0 && stringified !== '[object Object]' ? stringified : null;
    }

    return null;
  }

  private async loadMembers(force = false): Promise<void> {
    if (!force && (this.members().length || this.membersLoading())) {
      return;
    }

    this.membersLoading.set(true);
    this.membersError.set(null);

    try {
      const users = await this.usersService.listUsers();
      this.members.set(users);
    } catch (error) {
      this.membersError.set(error instanceof Error ? error.message : 'Unable to load team members.');
    } finally {
      this.membersLoading.set(false);
    }
  }

  private async hydrateParticipantNames(runs: RunOverviewEntry[]): Promise<void> {
    if (!runs.length) {
      this.participantNames.set({});
      return;
    }

    const names = this.applyParticipantNames(runs);
    const missingIds = new Set<string>();

    for (const run of runs) {
      if (run.pickerId && !names[run.pickerId]) {
        missingIds.add(run.pickerId);
      }
      if (run.runnerId && !names[run.runnerId]) {
        missingIds.add(run.runnerId);
      }
    }

    if (missingIds.size === 0) {
      this.participantNames.set(names);
      return;
    }

    this.loadingParticipantNames.set(true);
    try {
      const users = await this.usersService.lookupUsers([...missingIds]);
      for (const user of users) {
        const label = this.preferredName(user.firstName, user.lastName, user.email);
        if (label) {
          names[user.id] = label;
        }
      }
    } catch {
      // Ignore lookup failures; fallback names remain unchanged.
    } finally {
      this.loadingParticipantNames.set(false);
      this.participantNames.set(names);
    }
  }

  private applyParticipantNames(runs: RunOverviewEntry[]): Record<string, string> {
    const current = { ...this.participantNames() };

    for (const run of runs) {
      this.recordParticipantName(current, run.pickerId, run.pickerFirstName, run.pickerLastName);
      this.recordParticipantName(current, run.runnerId, run.runnerFirstName, run.runnerLastName);
    }

    this.participantNames.set(current);
    return current;
  }

  private recordParticipantName(
    target: Record<string, string>,
    userId: string | null,
    firstName: string | null,
    lastName: string | null,
  ): void {
    if (!userId) {
      return;
    }

    const label = this.preferredName(firstName, lastName);
    if (label) {
      target[userId] = label;
    }
  }

  private preferredName(
    firstName?: string | null,
    lastName?: string | null,
    fallback?: string | null,
  ): string | null {
    const primary = (firstName ?? '').trim();
    if (primary) {
      return primary;
    }

    const secondary = (lastName ?? '').trim();
    if (secondary) {
      return secondary;
    }

    const fallbackValue = (fallback ?? '').trim();
    return fallbackValue || null;
  }
}
