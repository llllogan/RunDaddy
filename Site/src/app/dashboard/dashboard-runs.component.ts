import { Component, computed, effect, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { formatDate } from '@angular/common';
import { RunsService, RunOverviewEntry, RunPerson } from './runs.service';
import { AuthService } from '../auth/auth.service';

@Component({
  selector: 'app-dashboard-runs',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard-runs.component.html',
})
export class DashboardRunsComponent {
  private readonly runsService = inject(RunsService);
  private readonly auth = inject(AuthService);
  private lastRunsCompanyId: string | null = null;

  protected readonly runs = signal<RunOverviewEntry[]>([]);
  protected readonly loadingRuns = signal(false);
  protected readonly runsError = signal<string | null>(null);

  protected readonly hasRuns = computed(() => this.runs().length > 0);
  protected readonly company = this.auth.company;

  constructor() {
    effect(() => {
      const companyId = this.company()?.id ?? null;
      if (!companyId) {
        this.runs.set([]);
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

  protected trackByRun = (_: number, run: RunOverviewEntry): string => run.id;

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
}
