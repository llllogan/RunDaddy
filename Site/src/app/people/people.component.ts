import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { finalize } from 'rxjs/operators';
import { PeopleService, CompanyPerson } from './people.service';
import { AuthService, UserRole } from '../auth/auth.service';

@Component({
  selector: 'app-people',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './people.component.html',
})
export class PeopleComponent implements OnInit {
  private readonly peopleService = inject(PeopleService);
  private readonly authService = inject(AuthService);
  private readonly cdr = inject(ChangeDetectorRef);

  readonly session$ = this.authService.session$;
  readonly roleOptions: ReadonlyArray<{ label: string; value: UserRole }> = [
    { label: 'Owner', value: 'OWNER' },
    { label: 'Admin', value: 'ADMIN' },
    { label: 'Picker', value: 'PICKER' },
    { label: 'God', value: 'GOD' },
  ];

  people: CompanyPerson[] = [];
  isLoading = false;
  errorMessage = '';
  private readonly updatingRoleIds = new Set<string>();
  private readonly removingIds = new Set<string>();

  ngOnInit(): void {
    this.loadPeople();
  }

  loadPeople(): void {
    this.isLoading = true;
    this.errorMessage = '';
    this.peopleService
      .listCompanyPeople()
      .pipe(
        finalize(() => {
          this.isLoading = false;
          this.markViewForCheck();
        }),
      )
      .subscribe({
        next: (people) => {
          this.people = people;
          this.markViewForCheck();
        },
        error: (error: Error) => {
          this.errorMessage = error.message;
          this.markViewForCheck();
        },
      });
  }

  trackByPersonId(_: number, person: CompanyPerson): string {
    return person.id;
  }

  isRoleBusy(personId: string): boolean {
    return this.updatingRoleIds.has(personId);
  }

  isRemoveBusy(personId: string): boolean {
    return this.removingIds.has(personId);
  }

  changeRole(person: CompanyPerson, role: UserRole): void {
    if (person.role === role || this.isRoleBusy(person.id)) {
      return;
    }
    this.updatingRoleIds.add(person.id);
    this.peopleService
      .updatePersonRole(person.id, role)
      .pipe(
        finalize(() => {
          this.updatingRoleIds.delete(person.id);
          this.markViewForCheck();
        }),
      )
      .subscribe({
        next: (updated) => {
          this.people = this.people.map((existing) =>
            existing.id === updated.id ? { ...existing, role: updated.role } : existing,
          );
          this.markViewForCheck();
        },
        error: (error: Error) => {
          this.errorMessage = error.message;
          this.markViewForCheck();
        },
      });
  }

  removePerson(person: CompanyPerson): void {
    if (this.isRemoveBusy(person.id)) {
      return;
    }
    const confirmed = confirm(`Remove ${person.firstName} ${person.lastName} from the company?`);
    if (!confirmed) {
      return;
    }
    this.removingIds.add(person.id);
    this.peopleService
      .removePerson(person.id)
      .pipe(
        finalize(() => {
          this.removingIds.delete(person.id);
          this.markViewForCheck();
        }),
      )
      .subscribe({
        next: () => {
          this.people = this.people.filter((existing) => existing.id !== person.id);
          this.markViewForCheck();
        },
        error: (error: Error) => {
          this.errorMessage = error.message;
          this.markViewForCheck();
        },
      });
  }

  private markViewForCheck(): void {
    this.cdr.detectChanges();
  }
}
