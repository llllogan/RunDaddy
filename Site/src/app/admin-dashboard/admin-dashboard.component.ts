import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { finalize } from 'rxjs/operators';
import {
  AdminDashboardService,
  AdminCompanyDetail,
  AdminCompanySummary,
} from './admin-dashboard.service';

@Component({
  selector: 'app-admin-dashboard',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './admin-dashboard.component.html',
})
export class AdminDashboardComponent implements OnInit {
  private readonly adminService = inject(AdminDashboardService);
  private readonly cdr = inject(ChangeDetectorRef);

  companies: AdminCompanySummary[] = [];
  selectedCompany: AdminCompanyDetail | null = null;
  selectedCompanyId: string | null = null;

  isLoadingCompanies = false;
  isLoadingDetail = false;
  listError = '';
  detailError = '';
  isDeletingCompany = false;
  deleteError = '';
  isConfirmingDelete = false;

  ngOnInit(): void {
    this.loadCompanies();
  }

  loadCompanies(): void {
    this.isLoadingCompanies = true;
    this.listError = '';
    this.adminService
      .getCompanies()
      .pipe(
        finalize(() => {
          this.isLoadingCompanies = false;
          this.markViewForCheck();
        }),
      )
      .subscribe({
        next: (companies) => {
          this.companies = companies;
          if (!companies.length) {
            this.selectedCompany = null;
            this.selectedCompanyId = null;
            this.detailError = '';
          } else if (!this.selectedCompanyId || !companies.some((company) => company.id === this.selectedCompanyId)) {
            this.selectCompany(companies[0]!.id);
          } else {
            this.selectCompany(this.selectedCompanyId);
          }
          this.markViewForCheck();
        },
        error: (error: Error) => {
          this.listError = error.message;
          this.companies = [];
          this.selectedCompany = null;
          this.selectedCompanyId = null;
          this.markViewForCheck();
        },
      });
  }

  selectCompany(companyId: string): void {
    if (!companyId) {
      return;
    }
    if (companyId === this.selectedCompanyId && this.isLoadingDetail) {
      return;
    }
    this.selectedCompanyId = companyId;
    this.selectedCompany = null;
    this.detailError = '';
    this.deleteError = '';
    this.isConfirmingDelete = false;
    this.isLoadingDetail = true;

    this.adminService
      .getCompany(companyId)
      .pipe(
        finalize(() => {
          this.isLoadingDetail = false;
          this.markViewForCheck();
        }),
      )
      .subscribe({
        next: (company) => {
          this.selectedCompany = company;
          this.markViewForCheck();
        },
        error: (error: Error) => {
          this.detailError = error.message;
          this.selectedCompany = null;
          this.markViewForCheck();
        },
      });
  }

  promptDeleteCompany(): void {
    if (!this.selectedCompany || this.isDeletingCompany || this.isLoadingDetail) {
      return;
    }
    this.deleteError = '';
    this.isConfirmingDelete = true;
  }

  cancelDelete(): void {
    this.isConfirmingDelete = false;
  }

  confirmDeleteCompany(): void {
    const companyId = this.selectedCompanyId;
    if (!companyId || this.isDeletingCompany) {
      return;
    }

    this.isDeletingCompany = true;
    this.isConfirmingDelete = false;
    this.deleteError = '';

    this.adminService
      .deleteCompany(companyId)
      .pipe(
        finalize(() => {
          this.isDeletingCompany = false;
          this.markViewForCheck();
        }),
      )
      .subscribe({
        next: () => {
          this.selectedCompany = null;
          this.selectedCompanyId = null;
          this.loadCompanies();
        },
        error: (error: Error) => {
          this.deleteError = error.message;
          this.markViewForCheck();
        },
      });
  }

  trackByCompanyId(_: number, company: AdminCompanySummary): string {
    return company.id;
  }

  trackByMemberId(_: number, member: { id: string }): string {
    return member.id;
  }

  trackByRunId(_: number, run: { id: string }): string {
    return run.id;
  }

  private markViewForCheck(): void {
    this.cdr.detectChanges();
  }
}
