import { Component, computed, effect, inject, signal } from '@angular/core';
import { CommonModule, formatDate } from '@angular/common';
import { RunsService, RunOverviewEntry, RunAssignmentRole, RunDetails } from './runs.service';
import { AuthService } from '../auth/auth.service';
import { UsersService, DashboardUser } from './users.service';

type ExplorerPickEntry = {
  id: string;
  skuLabel: string;
  skuCode: string;
  status: string;
  count: number;
  pickedAt: Date | null;
  coilCode: string | null;
  par: number | null;
};

type ExplorerMachine = {
  id: string;
  label: string;
  description: string | null;
  locationId: string;
  pickEntries: ExplorerPickEntry[];
};

type ExplorerLocation = {
  id: string;
  label: string;
  machines: ExplorerMachine[];
};

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
  protected readonly explorerRunId = signal<string | null>(null);
  protected readonly explorerRunDetails = signal<RunDetails | null>(null);
  protected readonly explorerLocations = signal<ExplorerLocation[]>([]);
  protected readonly explorerLoading = signal(false);
  protected readonly explorerError = signal<string | null>(null);
  protected readonly explorerSelectedLocation = signal<string | null>(null);
  protected readonly explorerSelectedMachine = signal<string | null>(null);
  protected readonly isExplorerOpen = computed(() => this.explorerRunId() !== null);
  protected readonly activeExplorerMachines = computed(() => {
    const locationId = this.explorerSelectedLocation();
    if (!locationId) {
      return [] as ExplorerMachine[];
    }
    const location = this.explorerLocations().find((candidate) => candidate.id === locationId);
    return location?.machines ?? [];
  });
  protected readonly activeExplorerEntries = computed(() => {
    const machineId = this.explorerSelectedMachine();
    if (!machineId) {
      return [] as ExplorerPickEntry[];
    }
    const machine = this.activeExplorerMachines().find((candidate) => candidate.id === machineId);
    return machine?.pickEntries ?? [];
  });

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
      CREATED: 'border border-rd-primary/12 bg-white/75 text-rd-secondary',
      PICKING: 'border border-rd-accent/30 bg-rd-accent/10 text-rd-accent',
      PICKED: 'border border-rd-accent/30 bg-rd-accent/10 text-rd-accent',
      IN_PROGRESS: 'border border-rd-accent/30 bg-rd-accent/10 text-rd-accent',
      COMPLETED: 'border border-rd-teal/30 bg-rd-teal/10 text-rd-teal',
      CANCELLED: 'border border-[#f87171]/30 bg-[#f87171]/10 text-[#c24141]',
      HISTORICAL: 'border border-rd-primary/12 bg-white/60 text-rd-secondary',
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

  protected openRunExplorer(run: RunOverviewEntry): void {
    if (this.explorerLoading() && this.explorerRunId() === run.id) {
      return;
    }
    const requestedRunId = run.id;
    this.explorerRunId.set(requestedRunId);
    this.explorerRunDetails.set(null);
    this.explorerLocations.set([]);
    this.explorerError.set(null);
    this.explorerSelectedLocation.set(null);
    this.explorerSelectedMachine.set(null);
    this.explorerLoading.set(true);

    void this.runsService
      .getRunDetails(requestedRunId)
      .then((details) => {
        if (this.explorerRunId() !== requestedRunId) {
          return;
        }
        this.explorerRunDetails.set(details);
        const locations = this.buildExplorerLocations(details);
        this.explorerLocations.set(locations);
        const firstLocation = locations[0] ?? null;
        this.explorerSelectedLocation.set(firstLocation?.id ?? null);
        const firstMachine = firstLocation?.machines[0] ?? null;
        this.explorerSelectedMachine.set(firstMachine?.id ?? null);
      })
      .catch((error) => {
        if (this.explorerRunId() !== requestedRunId) {
          return;
        }
        this.explorerError.set(error instanceof Error ? error.message : 'Unable to load run details.');
      })
      .finally(() => {
        if (this.explorerRunId() === requestedRunId) {
          this.explorerLoading.set(false);
        }
      });
  }

  protected closeRunExplorer(): void {
    this.explorerRunId.set(null);
    this.explorerRunDetails.set(null);
    this.explorerLocations.set([]);
    this.explorerSelectedLocation.set(null);
    this.explorerSelectedMachine.set(null);
    this.explorerError.set(null);
    this.explorerLoading.set(false);
  }

  protected selectExplorerLocation(locationId: string): void {
    this.explorerSelectedLocation.set(locationId);
    const location = this.explorerLocations().find((candidate) => candidate.id === locationId);
    this.explorerSelectedMachine.set(location?.machines[0]?.id ?? null);
  }

  protected selectExplorerMachine(machineId: string): void {
    this.explorerSelectedMachine.set(machineId);
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

    if (value && typeof value === 'object') {
      const candidate = value as { type?: unknown; data?: unknown };
      if (candidate.type === 'Buffer' && Array.isArray(candidate.data)) {
        const buffer = Uint8Array.from(candidate.data as number[]);
        const decoded = new TextDecoder().decode(buffer).replace(/\0+$/, '').trim();
        return decoded.length > 0 ? decoded : null;
      }
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

  private buildExplorerLocations(details: RunDetails): ExplorerLocation[] {
    const locationMap = new Map<string, ExplorerLocation>();
    const machineMap = new Map<string, ExplorerMachine>();

    const ensureLocation = (machine: RunDetails['pickEntries'][number]['coilItem']['coil']['machine'] | RunDetails['chocolateBoxes'][number]['machine'] | null): ExplorerLocation => {
      const inferredId = machine?.location?.id ?? 'location-unassigned';
      const label = (machine?.location?.name ?? '').trim() || 'Unassigned location';
      let location = locationMap.get(inferredId);
      if (!location) {
        location = {
          id: inferredId,
          label,
          machines: [],
        };
        locationMap.set(inferredId, location);
      }
      return location;
    };

    const ensureMachine = (
      machine: RunDetails['pickEntries'][number]['coilItem']['coil']['machine'] | RunDetails['chocolateBoxes'][number]['machine'] | null,
      fallbackId: string,
      fallbackLabel: string,
    ): ExplorerMachine => {
      const location = ensureLocation(machine);
      const machineId = machine?.id ?? fallbackId;
      let record = machineMap.get(machineId);
      if (!record) {
        record = {
          id: machineId,
          label: fallbackLabel,
          description: (machine?.description ?? '').trim() || null,
          locationId: location.id,
          pickEntries: [],
        };
        machineMap.set(machineId, record);
        location.machines.push(record);
      }
      return record;
    };

    for (const entry of details.pickEntries) {
      const machine = entry.coilItem.coil.machine;
      const fallbackId = machine?.id ?? `coil-${entry.coilItem.coil.id}`;
      const fallbackLabel =
        (machine?.code ?? '').trim() ||
        (entry.coilItem.coil.code ?? '').trim() ||
        'Unknown machine';
      const machineRecord = ensureMachine(machine, fallbackId, fallbackLabel);
      machineRecord.pickEntries.push({
        id: entry.id,
        skuLabel: (entry.coilItem.sku?.name ?? '').trim() || 'Unnamed SKU',
        skuCode: (entry.coilItem.sku?.code ?? '').trim() || '—',
        status: entry.status,
        count: entry.count,
        pickedAt: entry.pickedAt,
        coilCode: entry.coilItem.coil.code ?? null,
        par: entry.coilItem.par ?? null,
      });
    }

    for (const box of details.chocolateBoxes) {
      const machine = box.machine;
      if (!machine) {
        continue;
      }
      const fallbackLabel = (machine.code ?? '').trim() || `Machine ${box.number}`;
      ensureMachine(machine, machine.id ?? `chocolate-${box.id}`, fallbackLabel);
    }

    return Array.from(locationMap.values()).map((location) => ({
      ...location,
      machines: location.machines.map((machine) => ({
        ...machine,
        pickEntries: [...machine.pickEntries],
      })),
    }));
  }
}
