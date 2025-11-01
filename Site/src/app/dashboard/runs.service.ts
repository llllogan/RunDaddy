import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../config/api.config';

export type RunAssignmentRole = 'PICKER' | 'RUNNER';

export interface RunOverviewEntry {
  id: string;
  status: string;
  pickerId: string | null;
  pickerFirstName: string | null;
  pickerLastName: string | null;
  runnerId: string | null;
  runnerFirstName: string | null;
  runnerLastName: string | null;
  companyId: string;
  pickingStartedAt: Date | null;
  pickingEndedAt: Date | null;
  scheduledFor: Date | null;
  createdAt: Date;
}

export interface RunParticipant {
  id: string;
  firstName: string | null;
  lastName: string | null;
}

export interface RunLocation {
  id: string;
  name: string | null;
  address: string | null;
}

export interface RunMachine {
  id: string;
  code: string | null;
  description: string | null;
  location: RunLocation | null;
}

export interface RunSku {
  id: string;
  code: string;
  name: string;
  type: string;
}

export interface RunCoilItem {
  id: string;
  par: number | null;
  coil: {
    id: string;
    code: string | null;
    machine: RunMachine | null;
  };
  sku: RunSku | null;
}

export interface RunPickEntry {
  id: string;
  count: number;
  status: string;
  pickedAt: Date | null;
  coilItem: RunCoilItem;
}

export interface RunChocolateBox {
  id: string;
  number: number;
  machine: RunMachine | null;
}

export interface RunDetails {
  id: string;
  status: string;
  companyId: string;
  scheduledFor: Date | null;
  pickingStartedAt: Date | null;
  pickingEndedAt: Date | null;
  createdAt: Date;
  picker: RunParticipant | null;
  runner: RunParticipant | null;
  pickEntries: RunPickEntry[];
  chocolateBoxes: RunChocolateBox[];
}

interface RunOverviewResponse {
  id: string;
  status: string;
  pickerId: string | null;
  pickerFirstName: string | null;
  pickerLastName: string | null;
  runnerId: string | null;
  runnerFirstName: string | null;
  runnerLastName: string | null;
  companyId: string;
  pickingStartedAt: string | null;
  pickingEndedAt: string | null;
  scheduledFor: string | null;
  createdAt: string;
}

interface RunAssignmentResponse {
  id: string;
  status: string;
  companyId: string;
  pickingStartedAt: string | null;
  pickingEndedAt: string | null;
  scheduledFor: string | null;
  createdAt: string;
  picker: {
    id: string;
    firstName: string | null;
    lastName: string | null;
  } | null;
  runner: {
    id: string;
    firstName: string | null;
    lastName: string | null;
  } | null;
}

interface RunParticipantResponse {
  id: string;
  firstName: string | null;
  lastName: string | null;
}

interface RunLocationResponse {
  id: string;
  name: string | null;
  address: string | null;
}

interface RunMachineResponse {
  id: string;
  code: string | null;
  description: string | null;
  location: RunLocationResponse | null;
}

interface RunSkuResponse {
  id: string;
  code: string;
  name: string;
  type: string;
}

interface RunCoilItemResponse {
  id: string;
  par: number | null;
  coil: {
    id: string;
    code: string | null;
    machine: RunMachineResponse | null;
  };
  sku: RunSkuResponse | null;
}

interface RunPickEntryResponse {
  id: string;
  count: number;
  status: string;
  pickedAt: string | null;
  coilItem: RunCoilItemResponse;
}

interface RunChocolateBoxResponse {
  id: string;
  number: number;
  machine: RunMachineResponse | null;
}

interface RunDetailsResponse {
  id: string;
  status: string;
  companyId: string;
  scheduledFor: string | null;
  pickingStartedAt: string | null;
  pickingEndedAt: string | null;
  createdAt: string;
  picker: RunParticipantResponse | null;
  runner: RunParticipantResponse | null;
  pickEntries: RunPickEntryResponse[];
  chocolateBoxes: RunChocolateBoxResponse[];
}

@Injectable({
  providedIn: 'root',
})
export class RunsService {
  private readonly http = inject(HttpClient);

  async getOverview(): Promise<RunOverviewEntry[]> {
    try {
      const response = await firstValueFrom(
        this.http.get<RunOverviewResponse[]>(`${API_BASE_URL}/runs/overview`),
      );
      return response.map((run) => this.toRunOverviewEntry(run));
    } catch (error) {
      throw this.toError(error);
    }
  }

  async getRunDetails(runId: string): Promise<RunDetails> {
    try {
      const response = await firstValueFrom(
        this.http.get<RunDetailsResponse>(`${API_BASE_URL}/runs/${runId}`),
      );
      return this.toRunDetails(response);
    } catch (error) {
      throw this.toError(error);
    }
  }

  async assignParticipant(runId: string, userId: string, role: RunAssignmentRole): Promise<RunOverviewEntry> {
    try {
      const response = await firstValueFrom(
        this.http.post<RunAssignmentResponse>(`${API_BASE_URL}/runs/${runId}/assignment`, {
          userId,
          role,
        }),
      );

      const normalized: RunOverviewResponse = {
        id: response.id,
        status: response.status,
        companyId: response.companyId,
        pickerId: response.picker?.id ?? null,
        pickerFirstName: response.picker?.firstName ?? null,
        pickerLastName: response.picker?.lastName ?? null,
        runnerId: response.runner?.id ?? null,
        runnerFirstName: response.runner?.firstName ?? null,
        runnerLastName: response.runner?.lastName ?? null,
        pickingStartedAt: response.pickingStartedAt,
        pickingEndedAt: response.pickingEndedAt,
        scheduledFor: response.scheduledFor,
        createdAt: response.createdAt,
      };

      return this.toRunOverviewEntry(normalized);
    } catch (error) {
      throw this.toError(error);
    }
  }

  private toRunOverviewEntry(run: RunOverviewResponse): RunOverviewEntry {
    return {
      id: run.id,
      status: run.status,
      companyId: run.companyId,
      pickerId: run.pickerId,
      pickerFirstName: run.pickerFirstName,
      pickerLastName: run.pickerLastName,
      runnerId: run.runnerId,
      runnerFirstName: run.runnerFirstName,
      runnerLastName: run.runnerLastName,
      pickingStartedAt: this.parseDate(run.pickingStartedAt),
      pickingEndedAt: this.parseDate(run.pickingEndedAt),
      scheduledFor: this.parseDate(run.scheduledFor),
      createdAt: this.parseDate(run.createdAt) ?? new Date(),
    };
  }

  private toRunDetails(run: RunDetailsResponse): RunDetails {
    return {
      id: run.id,
      status: run.status,
      companyId: run.companyId,
      scheduledFor: this.parseDate(run.scheduledFor),
      pickingStartedAt: this.parseDate(run.pickingStartedAt),
      pickingEndedAt: this.parseDate(run.pickingEndedAt),
      createdAt: this.parseDate(run.createdAt) ?? new Date(),
      picker: this.toParticipant(run.picker),
      runner: this.toParticipant(run.runner),
      pickEntries: run.pickEntries.map((entry) => this.toPickEntry(entry)),
      chocolateBoxes: run.chocolateBoxes.map((box) => this.toChocolateBox(box)),
    };
  }

  private toParticipant(participant: RunParticipantResponse | null): RunParticipant | null {
    if (!participant) {
      return null;
    }
    return {
      id: participant.id,
      firstName: participant.firstName,
      lastName: participant.lastName,
    };
  }

  private toPickEntry(entry: RunPickEntryResponse): RunPickEntry {
    return {
      id: entry.id,
      count: entry.count,
      status: entry.status,
      pickedAt: this.parseDate(entry.pickedAt),
      coilItem: this.toCoilItem(entry.coilItem),
    };
  }

  private toChocolateBox(box: RunChocolateBoxResponse): RunChocolateBox {
    return {
      id: box.id,
      number: box.number,
      machine: this.toMachine(box.machine),
    };
  }

  private toCoilItem(item: RunCoilItemResponse): RunCoilItem {
    return {
      id: item.id,
      par: item.par ?? null,
      coil: {
        id: item.coil.id,
        code: item.coil.code ?? null,
        machine: this.toMachine(item.coil.machine),
      },
      sku: item.sku ? this.toSku(item.sku) : null,
    };
  }

  private toMachine(machine: RunMachineResponse | null): RunMachine | null {
    if (!machine) {
      return null;
    }
    return {
      id: machine.id,
      code: machine.code ?? null,
      description: machine.description ?? null,
      location: machine.location ? this.toLocation(machine.location) : null,
    };
  }

  private toLocation(location: RunLocationResponse | null): RunLocation | null {
    if (!location) {
      return null;
    }
    return {
      id: location.id,
      name: location.name,
      address: location.address,
    };
  }

  private toSku(sku: RunSkuResponse): RunSku {
    return {
      id: sku.id,
      code: sku.code,
      name: sku.name,
      type: sku.type,
    };
  }

  private parseDate(value: string | null): Date | null {
    if (!value) {
      return null;
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
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
        'Unable to load run data.';
      return new Error(message);
    }
    if (error instanceof Error) {
      return error;
    }
    return new Error('Unable to load run data.');
  }
}
