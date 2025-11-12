import { Component } from '@angular/core';

@Component({
  selector: 'app-root',
  standalone: true,
  templateUrl: './app.component.html',
})
export class App {
  isDark = true;

  toggleTheme(): void {
    this.isDark = !this.isDark;
  }
}
