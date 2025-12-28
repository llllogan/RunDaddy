import { AsyncPipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { filter, map, startWith, take } from 'rxjs';
import { AuthService } from '@shared/auth/auth.service';
import { SHELL_CONFIG, ShellTab } from './shell-config';

@Component({
  selector: 'rd-shell-layout',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, AsyncPipe],
  templateUrl: './shell-layout.component.html',
})
export class ShellLayoutComponent implements OnInit {
  private readonly authService = inject(AuthService);
  private readonly router = inject(Router);
  private readonly shellConfig = inject(SHELL_CONFIG);

  readonly session$ = this.authService.session$;
  readonly headerTabs: ReadonlyArray<ShellTab> = this.shellConfig.tabs;

  readonly isAuthRoute$ = this.router.events.pipe(
    filter((event): event is NavigationEnd => event instanceof NavigationEnd),
    map((event) => event.urlAfterRedirects),
    startWith(this.router.url),
    map((url) => this.shellConfig.authRoutePrefixes.some((prefix) => url.startsWith(prefix))),
  );

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

