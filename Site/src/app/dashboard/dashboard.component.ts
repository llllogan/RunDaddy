import { Component, computed, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';

interface UploadedFile {
  file: File;
  receivedAt: Date;
}

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './dashboard.component.html',
})
export class DashboardComponent {
  protected readonly tabs = [
    { id: 'home', label: 'Home' },
    { id: 'pickers', label: 'Pickers' },
  ] as const;

  protected readonly activeTab = signal<'home' | 'pickers'>('home');
  protected readonly isDragging = signal(false);
  protected readonly uploadedFiles = signal<UploadedFile[]>([]);

  protected readonly hasFiles = computed(() => this.uploadedFiles().length > 0);

  protected setTab(tab: 'home' | 'pickers'): void {
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

  protected removeFile(index: number): void {
    const files = [...this.uploadedFiles()];
    files.splice(index, 1);
    this.uploadedFiles.set(files);
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
    const next = [
      ...this.uploadedFiles(),
      ...incoming.map((file) => ({ file, receivedAt: new Date() })),
    ];
    this.uploadedFiles.set(next);
  }
}
