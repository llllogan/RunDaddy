import { Component } from '@angular/core';
import { ShellLayoutComponent } from '@shared/layout/shell-layout.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [ShellLayoutComponent],
  template: '<rd-shell-layout />',
})
export class App {}

