import { Component, OnInit, inject } from '@angular/core';
import { NavigationEnd, Router, RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { AsyncPipe } from '@angular/common';
import { filter, map, startWith, take } from 'rxjs';
import { AuthService } from './auth/auth.service';

type HeaderTabId = 'runs' | 'people' | 'billing' | 'admin';

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
  private readonly router = inject(Router);
  readonly session$ = this.authService.session$;
  readonly isAuthRoute$ = this.router.events.pipe(
    filter((event): event is NavigationEnd => event instanceof NavigationEnd),
    map((event) => event.urlAfterRedirects),
    startWith(this.router.url),
    map((url) => url.startsWith('/login') || url.startsWith('/signup')),
  );
  readonly headerTabs: ReadonlyArray<HeaderTab> = [
    { id: 'runs', label: 'Runs', route: '/dashboard/runs' },
    { id: 'people', label: 'People', route: '/dashboard/people' },
    { id: 'billing', label: 'Billing', route: '/dashboard/billing' },
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
