import { Component, OnInit, inject } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { AsyncPipe } from '@angular/common';
import { take } from 'rxjs';
import { AuthService } from './auth/auth.service';

type HeaderTabId = 'runs' | 'people' | 'admin';

interface HeaderTab {
  id: HeaderTabId;
  label: string;
  route: string;
  requiresAdminContext?: boolean;
}

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, AsyncPipe],
  templateUrl: './app.component.html',
})
export class App implements OnInit {
  private readonly authService = inject(AuthService);
  readonly session$ = this.authService.session$;
  readonly headerTabs: ReadonlyArray<HeaderTab> = [
    { id: 'runs', label: 'Runs', route: '/dashboard/runs' },
    { id: 'people', label: 'People', route: '/dashboard/people' },
    { id: 'admin', label: 'Admin', route: '/dashboard/admin', requiresAdminContext: true },
  ];

  ngOnInit(): void {
    this.authService.ensureBootstrap();
  }

  onLogout(): void {
    this.authService
      .logout()
      .pipe(take(1))
      .subscribe();
  }
}
