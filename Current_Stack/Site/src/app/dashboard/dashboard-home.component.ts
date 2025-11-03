import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { RunImportsService } from './run-imports.service';

@Component({
  selector: 'app-dashboard-home',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard-home.component.html',
})
export class DashboardHomeComponent {
  private readonly router = inject(Router);
  private readonly runImportsService = inject(RunImportsService);

  protected readonly isDragging = signal(false);
  protected readonly uploadingRun = signal(false);
  protected readonly uploadError = signal<string | null>(null);

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
    if (!incoming.length || this.uploadingRun()) {
      return;
    }
    const [file] = incoming;
    if (!file) {
      return;
    }
    void this.processRunUpload(file);
  }

  private async processRunUpload(file: File): Promise<void> {
    if (this.uploadingRun()) {
      return;
    }
    this.uploadingRun.set(true);
    this.uploadError.set(null);

    try {
      await this.runImportsService.uploadRun(file);
      // Navigate to runs so the dedicated page can pull the latest overview.
      await this.router.navigate(['/dashboard', 'runs']);
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'Unable to process this workbook. Please try again.';
      this.uploadError.set(message);
    } finally {
      this.uploadingRun.set(false);
    }
  }
}
