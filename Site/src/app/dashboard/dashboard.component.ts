import { CommonModule } from '@angular/common';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { ChangeDetectorRef, Component, inject } from '@angular/core';
import { finalize } from 'rxjs';
import { AuthService } from '../auth/auth.service';
import { buildApiUrl } from '../config/runtime-env';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard.component.html',
})
export class DashboardComponent {
  private readonly authService = inject(AuthService);
  private readonly http = inject(HttpClient);
  private readonly cdr = inject(ChangeDetectorRef);
  readonly session$ = this.authService.session$;

  isDragging = false;
  isValidHover = false;
  isUploading = false;
  feedbackMessage = '';
  feedbackVariant: 'success' | 'error' | '' = '';
  lastUploadedFile = '';
  uploadSummary: RunImportSummary | null = null;

  handleDragOver(event: DragEvent): void {
    event.preventDefault();
    this.isDragging = true;
    this.isValidHover = this.hasValidFile(event.dataTransfer?.items ?? undefined);
  }

  handleDragLeave(event: DragEvent): void {
    event.preventDefault();
    const relatedTarget = event.relatedTarget as HTMLElement | null;
    if (!relatedTarget || !event.currentTarget) {
      this.resetDragState();
      return;
    }
    if (!(event.currentTarget as HTMLElement).contains(relatedTarget)) {
      this.resetDragState();
    }
  }

  handleDrop(event: DragEvent): void {
    event.preventDefault();
    const file = this.getFileFromDrop(event.dataTransfer);
    this.resetDragState();
    this.prepareUpload(file);
  }

  onFileInputChange(event: Event): void {
    const target = event.target as HTMLInputElement;
    const file = target?.files?.[0];
    this.prepareUpload(file ?? null);
    if (target) {
      target.value = '';
    }
  }

  private prepareUpload(file: File | null): void {
    if (!file) {
      return;
    }
    if (!this.isExcelFile(file)) {
      this.setFeedback('Please choose a .xlsx or .xls workbook.', 'error');
      return;
    }
    this.uploadFile(file);
  }

  private uploadFile(file: File): void {
    if (this.isUploading) {
      return;
    }
    this.isUploading = true;
    this.setFeedback('', '');
    this.uploadSummary = null;
    this.lastUploadedFile = file.name;
    const formData = new FormData();
    formData.append('file', file);

    this.http
      .post<RunImportResponse>(buildApiUrl('/run-imports/runs'), formData)
      .pipe(
        finalize(() => {
          this.isUploading = false;
          this.markViewForCheck();
        }),
      )
      .subscribe({
        next: (response) => {
          this.setFeedback(`Successfully uploaded ${file.name}.`, 'success');
          this.uploadSummary = response.summary;
          this.markViewForCheck();
        },
        error: (error: HttpErrorResponse) => {
          const message = error.error?.error ?? 'Unable to upload the run. Please try again.';
          this.setFeedback(message, 'error');
          this.markViewForCheck();
        },
      });
  }

  private getFileFromDrop(dataTransfer: DataTransfer | null): File | null {
    if (!dataTransfer) {
      return null;
    }
    if (dataTransfer.files?.length) {
      return dataTransfer.files[0];
    }
    if (dataTransfer.items?.length) {
      const item = dataTransfer.items[0];
      if (item.kind === 'file') {
        return item.getAsFile();
      }
    }
    return null;
  }

  private hasValidFile(items?: DataTransferItemList): boolean {
    if (!items || !items.length) {
      return false;
    }
    for (let i = 0; i < items.length; i += 1) {
      const item = items[i];
      if (item.kind === 'file') {
        const file = item.getAsFile();
        if (file && this.isExcelFile(file)) {
          return true;
        }
      }
    }
    return false;
  }

  private isExcelFile(file: File): boolean {
    const name = file.name.toLowerCase();
    return name.endsWith('.xlsx') || name.endsWith('.xls');
  }

  private resetDragState(): void {
    this.isDragging = false;
    this.isValidHover = false;
  }

  private setFeedback(message: string, variant: 'success' | 'error' | ''): void {
    this.feedbackMessage = message;
    this.feedbackVariant = variant;
  }

  private markViewForCheck(): void {
    this.cdr.detectChanges();
  }
}

type RunImportSummary = {
  runs: number;
  machines: number;
  pickEntries: number;
};

type RunImportResponse = {
  summary: RunImportSummary;
};
