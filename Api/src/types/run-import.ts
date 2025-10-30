export interface ParsedRunWorkbook {
  run: ParsedRun | null;
}

export interface ParsedRun {
  runDate: Date | null;
  pickEntries: ParsedPickEntry[];
}

export interface ParsedRunLocation {
  sheetName: string;
  name: string;
  address: string;
  runDate: Date | null;
  machines: ParsedRunMachine[];
}

export interface ParsedRunMachine {
  locationName: string;
  machineCode: string;
  machineName: string;
  runDate: Date | null;
  location: ParsedMachineLocation | null;
  machineType: ParsedMachineType | null;
  coilItems: ParsedCoilItemRow[];
}

export interface ParsedCoilItemRow {
  coilCode: string;
  sku: ParsedSku;
  current?: number | null;
  par?: number | null;
  need?: number | null;
  forecast?: number | null;
  total?: number | null;
  notes?: string | null;
}

export interface ParsedPickEntry {
  coilItem: ParsedCoilItem;
  count: number | null;
  current: number | null;
  par: number | null;
  need: number | null;
  forecast: number | null;
  notes: string | null;
}

export interface ParsedCoilItem {
  sku: ParsedSku;
  coil: ParsedCoil;
}

export interface ParsedCoil {
  code: string;
  machine: ParsedMachine;
}

export interface ParsedMachine {
  code: string;
  name: string;
  runDate: Date | null;
  machineType: ParsedMachineType | null;
  location: ParsedMachineLocation | null;
}

export interface ParsedSku {
  code: string;
  name: string;
  type?: string | null;
}

export interface ParsedMachineLocation {
  name: string;
  address: string | null;
}

export interface ParsedMachineType {
  name: string;
  category: string | null;
}
