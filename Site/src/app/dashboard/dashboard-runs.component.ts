import { Component, computed, effect, inject, signal } from '@angular/core';
import { CommonModule, formatDate } from '@angular/common';
import { RunsService, RunDetail, RunOverviewEntry, RunPerson } from './runs.service';
import { AuthService } from '../auth/auth.service';
import { LocationsService, LocationSummary } from './locations.service';

interface RunDetailPickEntryView {
  id: string;
  skuCode: string;
  skuName: string;
  status: string;
  count: number;
  par: number;
  coilCode: string;
  pickedAt: Date | null;
}

interface RunMachineGroup {
  id: string;
  code: string;
  description: string | null;
  totalCount: number;
  pickEntries: RunDetailPickEntryView[];
}

interface RunLocationGroup {
  id: string | null;
  name: string;
  totalCount: number;
  machines: RunMachineGroup[];
}

interface RunDetailHierarchy {
  runId: string;
  totalCount: number;
  totalDistinctItems: number;
  locations: RunLocationGroup[];
}

@Component({
  selector: 'app-dashboard-runs',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard-runs.component.html',
})
export class DashboardRunsComponent {
  private readonly runsService = inject(RunsService);
  private readonly auth = inject(AuthService);
  private readonly locationsService = inject(LocationsService);
  private lastRunsCompanyId: string | null = null;
  private lastLocationsCompanyId: string | null = null;

  protected readonly runs = signal<RunOverviewEntry[]>([]);
  protected readonly loadingRuns = signal(false);
  protected readonly runsError = signal<string | null>(null);
  protected readonly loadingLocations = signal(false);
  protected readonly locationsError = signal<string | null>(null);
  protected readonly locations = signal<Record<string, LocationSummary>>({});
  protected readonly expandedRuns = signal<Set<string>>(new Set());
  protected readonly runDetails = signal<Record<string, RunDetailHierarchy>>({});
  protected readonly runDetailsLoading = signal<Record<string, boolean>>({});
  protected readonly runDetailsError = signal<Record<string, string | null>>({});

  protected readonly hasRuns = computed(() => this.runs().length > 0);
  protected readonly company = this.auth.company;

  constructor() {
    effect(() => {
      const companyId = this.company()?.id ?? null;
      if (!companyId) {
        this.runs.set([]);
        this.locations.set({});
        this.locationsError.set(null);
        this.lastRunsCompanyId = null;
        this.lastLocationsCompanyId = null;
        this.expandedRuns.set(new Set());
        this.runDetails.set({});
        this.runDetailsLoading.set({});
        this.runDetailsError.set({});
        return;
      }

      this.expandedRuns.set(new Set());
      this.runDetails.set({});
      this.runDetailsLoading.set({});
      this.runDetailsError.set({});

      void this.loadRuns(companyId);
      void this.loadLocations(companyId);
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
    void this.loadLocations(companyId, true);
  }

  protected reloadRunDetail(runId: string): void {
    void this.loadRunDetail(runId, true);
  }

  protected trackByRun = (_: number, run: RunOverviewEntry): string => run.id;

  protected isRunExpanded(runId: string): boolean {
    return this.expandedRuns().has(runId);
  }

  protected toggleRunDetails(runId: string): void {
    const expanded = new Set(this.expandedRuns());
    if (expanded.has(runId)) {
      expanded.delete(runId);
      this.expandedRuns.set(expanded);
      return;
    }

    expanded.add(runId);
    this.expandedRuns.set(expanded);

    if (!this.runDetails()[runId]) {
      void this.loadRunDetail(runId);
    }
  }

  protected isLoadingRunDetail(runId: string): boolean {
    return this.runDetailsLoading()[runId] ?? false;
  }

  protected runDetailErrorFor(runId: string): string | null {
    return this.runDetailsError()[runId] ?? null;
  }

  protected runDetailFor(runId: string): RunDetailHierarchy | null {
    return this.runDetails()[runId] ?? null;
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

  protected pickStatusBadgeClass(status: string): string {
    const mapping: Record<string, string> = {
      PICKED: 'border border-rd-teal/30 bg-rd-teal/10 text-rd-teal',
      PENDING: 'border border-[#f9c74f]/40 bg-[#f9c74f]/10 text-[#a16207]',
      SKIPPED: 'border border-[#f87171]/30 bg-[#f87171]/10 text-[#c24141]',
    };
    return mapping[status] ?? 'border border-rd-primary/12 bg-white/80 text-rd-secondary';
  }

  protected formatPerson(person: RunPerson | null): string {
    if (!person) {
      return '—';
    }
    const parts = [person.firstName, person.lastName].filter(Boolean);
    return parts.length ? parts.join(' ') : person.id;
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

  private async loadLocations(companyId: string, force = false): Promise<void> {
    if (!force && companyId === this.lastLocationsCompanyId) {
      return;
    }

    this.loadingLocations.set(true);
    this.locationsError.set(null);

    try {
      const list = await this.locationsService.listLocations();
      const map = list.reduce<Record<string, LocationSummary>>((acc, location) => {
        acc[location.id] = location;
        return acc;
      }, {});
      this.locations.set(map);
      this.lastLocationsCompanyId = companyId;
    } catch (error) {
      this.locationsError.set(error instanceof Error ? error.message : 'Unable to load locations.');
      if (!force) {
        this.lastLocationsCompanyId = null;
      }
    } finally {
      this.loadingLocations.set(false);
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

  private async loadRunDetail(runId: string, force = false): Promise<void> {
    if (!force && this.runDetails()[runId]) {
      return;
    }

    this.runDetailsLoading.update((current) => ({ ...current, [runId]: true }));
    this.runDetailsError.update((current) => ({ ...current, [runId]: null }));

    try {
      const detail = await this.runsService.getRunDetail(runId);
      const structured = this.buildRunHierarchy(detail);

      this.runDetails.update((current) => ({
        ...current,
        [runId]: structured,
      }));
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to load run details.';
      this.runDetailsError.update((current) => ({ ...current, [runId]: message }));
    } finally {
      this.runDetailsLoading.update((current) => ({ ...current, [runId]: false }));
    }
  }

  private buildRunHierarchy(detail: RunDetail): RunDetailHierarchy {
    const locationsIndex = this.locations();
    const loadingLocations = this.loadingLocations();

    const locationAccumulator = new Map<
      string | null,
      { id: string | null; name: string; machines: Map<string, RunMachineGroup> }
    >();

    detail.pickEntries.forEach((entry) => {
      const locationId = entry.coil.machine.locationId ?? null;
      const machineId = entry.coil.machine.id;

      let locationGroup = locationAccumulator.get(locationId);
      if (!locationGroup) {
        const lookup = locationId ? locationsIndex[locationId] : null;
        const name = locationId
          ? lookup?.name ?? (loadingLocations ? 'Loading location…' : 'Unknown location')
          : 'Unassigned location';
        locationGroup = {
          id: locationId,
          name,
          machines: new Map(),
        };
        locationAccumulator.set(locationId, locationGroup);
      }

      let machineGroup = locationGroup.machines.get(machineId);
      if (!machineGroup) {
        machineGroup = {
          id: machineId,
          code: entry.coil.machine.code,
          description: entry.coil.machine.description ?? null,
          totalCount: 0,
          pickEntries: [],
        };
        locationGroup.machines.set(machineId, machineGroup);
      }

      const viewEntry: RunDetailPickEntryView = {
        id: entry.id,
        skuCode: entry.sku.code,
        skuName: entry.sku.name,
        status: entry.status,
        count: entry.count,
        par: entry.par,
        coilCode: entry.coil.code,
        pickedAt: entry.pickedAt,
      };

      machineGroup.pickEntries.push(viewEntry);
      machineGroup.totalCount += entry.count;
    });

    const locations: RunLocationGroup[] = Array.from(locationAccumulator.values()).map(
      (locationGroup) => {
        const machines = Array.from(locationGroup.machines.values())
          .map((machine) => ({
            ...machine,
            pickEntries: [...machine.pickEntries].sort((a, b) =>
              a.skuName.localeCompare(b.skuName, 'en-US', { sensitivity: 'base' }),
            ),
          }))
          .sort((a, b) => a.code.localeCompare(b.code, 'en-US', { sensitivity: 'base' }));

        const totalCount = machines.reduce((sum, machine) => sum + machine.totalCount, 0);
        return {
          id: locationGroup.id,
          name: locationGroup.name,
          machines,
          totalCount,
        };
      },
    );

    locations.sort((a, b) => a.name.localeCompare(b.name, 'en-US', { sensitivity: 'base' }));

    const totalCount = locations.reduce((sum, location) => sum + location.totalCount, 0);

    return {
      runId: detail.id,
      totalCount,
      totalDistinctItems: detail.pickEntries.length,
      locations,
    };
  }
}
