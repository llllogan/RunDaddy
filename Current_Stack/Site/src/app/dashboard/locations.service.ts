import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../config/api.config';

export interface LocationSummary {
  id: string;
  name: string;
  address: string | null;
}

interface LocationResponseItem {
  id: string;
  name: string;
  address: string | null;
}

@Injectable({
  providedIn: 'root',
})
export class LocationsService {
  private readonly http = inject(HttpClient);

  async listLocations(): Promise<LocationSummary[]> {
    try {
      const response = await firstValueFrom(
        this.http.get<LocationResponseItem[]>(`${API_BASE_URL}/locations`),
      );

      return response.map((location) => ({
        id: location.id,
        name: location.name,
        address: location.address,
      }));
    } catch (error) {
      throw this.toError(error);
    }
  }

  private toError(error: unknown): Error {
    if (error instanceof HttpErrorResponse) {
      const message =
        (typeof error.error === 'object' &&
          error.error &&
          'error' in error.error &&
          typeof error.error.error === 'string'
          ? error.error.error
          : null) ??
        error.message ??
        'Unable to load locations.';
      return new Error(message);
    }
    if (error instanceof Error) {
      return error;
    }
    return new Error('Unable to load locations.');
  }
}
