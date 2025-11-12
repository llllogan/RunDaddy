import { Component, OnInit, inject } from '@angular/core';
import { RouterOutlet, RouterLink } from '@angular/router';
import { NgIf, AsyncPipe } from '@angular/common';
import { take } from 'rxjs';
import { AuthService } from './auth/auth.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink, NgIf, AsyncPipe],
  templateUrl: './app.component.html',
})
export class App implements OnInit {
  private readonly authService = inject(AuthService);
  readonly session$ = this.authService.session$;

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
