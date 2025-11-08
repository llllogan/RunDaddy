import pkg from 'exceljs';
import { Readable } from 'stream';

const { Workbook } = pkg;
type Worksheet = pkg.Worksheet;
import type {
  ParsedCoilItem,
  ParsedCoilItemRow,
  ParsedRun,
  ParsedRunLocation,
  ParsedRunMachine,
  ParsedRunWorkbook,
  ParsedPickEntry,
  ParsedSku,
  ParsedMachine,
  ParsedMachineLocation,
  ParsedMachineType,
  ParsedCoil,
} from '../types/run-import.js';

const MACHINE_HEADER_MARKER = ' - Machine ';
const LOCATION_PREFIX = 'Location:';

type SheetRow = Array<string | number | null | undefined>;

export const parseRunWorkbook = async (workbookBuffer: Buffer): Promise<ParsedRunWorkbook> => {
  const workbook = new Workbook();
  const stream = Readable.from(workbookBuffer);
  await workbook.xlsx.read(stream);
  const locations: ParsedRunLocation[] = [];
  
  // Extract category from first sheet
  const firstWorksheet = workbook.worksheets[0];
  const globalCategory = firstWorksheet ? await extractCategoryFromSheet(firstWorksheet) : null;

  workbook.worksheets.slice(1).forEach((worksheet) => {
    if (!worksheet) {
      return;
    }
    const location = parseLocationSheet(worksheet, worksheet.name || '', globalCategory);
    if (location) {
      locations.push(location);
    }
  });

  if (!locations.length) {
    return { run: null };
  }

  const machines = locations.flatMap((location) => location.machines);
  const pickEntries = flattenPickEntries(machines);
  const runDate = deriveRunDate(locations);

  const run: ParsedRun = {
    runDate,
    pickEntries,
  };

  return { run };
};

const parseLocationSheet = (worksheet: Worksheet, sheetName: string, globalCategory: string | null): ParsedRunLocation | null => {
  const rows: SheetRow[] = [];
  worksheet.eachRow((row, rowNumber) => {
    if (rowNumber > 0) { // Skip header row in exceljs
      const rowData: SheetRow = [];
      row.eachCell((cell, colNumber) => {
        rowData[colNumber - 1] = cell.value?.toString() || '';
      });
      // Fill empty cells to maintain consistent row length
      while (rowData.length < worksheet.columnCount) {
        rowData.push('');
      }
      rows.push(rowData);
    }
  });

  if (!rows.length) {
    return null;
  }

  const locationHeader = getCellAsString(rows[0], 0);
  if (!locationHeader.startsWith(LOCATION_PREFIX)) {
    return null;
  }

  const { locationName, runDate } = parseLocationHeader(locationHeader);
  const address = getCellAsString(rows[1], 0);

  const machines: ParsedRunMachine[] = [];
  let index = 2;

  while (index < rows.length) {
    const row = rows[index];
    const headerValue = getCellAsString(row, 0);

    if (!headerValue) {
      index += 1;
      continue;
    }

    if (headerValue.includes(MACHINE_HEADER_MARKER)) {
      const { machine, nextIndex } = parseMachineBlock({
        rows,
        startIndex: index,
        locationName,
        locationAddress: address,
        globalCategory,
      });
      machines.push(machine);
      index = nextIndex;
      continue;
    }

    index += 1;
  }

  return {
    sheetName,
    name: locationName,
    address,
    runDate,
    machines,
  };
};

const parseMachineBlock = ({
  rows,
  startIndex,
  locationName,
  locationAddress,
  globalCategory,
}: {
  rows: SheetRow[];
  startIndex: number;
  locationName: string;
  locationAddress: string;
  globalCategory: string | null;
}): { machine: ParsedRunMachine; nextIndex: number } => {
  const machineHeaderRow = rows[startIndex];
  const machineInfoRow = rows[startIndex + 1] ?? [];

  const machineHeaderValue = getCellAsString(machineHeaderRow, 0);
  const machineInfoValue = getCellAsString(machineInfoRow, 0);

  const machineCode = parseMachineCode(machineHeaderValue, locationName);
  const { machineName, category, machineTypeName, runDate } = parseMachineInfo(machineInfoValue, globalCategory);

  let cursor = startIndex + 2;

  // Skip blank spacer rows between machine header and column headers
  while (cursor < rows.length && isRowEmpty(rows[cursor])) {
    cursor += 1;
  }

  // Expect the coil header row with known column headings
  const columnsRow: SheetRow = rows[cursor] ?? [];
  const isCoilHeaderRow = getCellAsString(columnsRow, 4).toLowerCase() === 'coil';
  if (!isCoilHeaderRow) {
    throw new Error(`Unexpected sheet format: missing coil header near row ${cursor + 1}`);
  }
  cursor += 1;

  const coilItems: ParsedCoilItemRow[] = [];

  while (cursor < rows.length) {
    const row: SheetRow = rows[cursor] ?? [];
    const firstCell = getCellAsString(row, 0);

    // A new machine block begins
    if (firstCell.includes(MACHINE_HEADER_MARKER)) {
      break;
    }

    const coilCode = getCellAsString(row, 4);
    const skuRaw = getCellAsString(row, 5);

    const isEndOfSection = !coilCode && !skuRaw && isRowMostlyEmpty(row);
    if (isEndOfSection) {
      cursor += 1;
      // Skip any blank rows before the next section
      while (cursor < rows.length && isRowEmpty(rows[cursor])) {
        cursor += 1;
      }
      break;
    }

    if (coilCode || skuRaw) {
      coilItems.push(parseCoilItem(row, globalCategory));
    }

    cursor += 1;
  }

  return {
    machine: {
      locationName,
      machineCode,
      machineName,
      runDate,
      location: {
        name: locationName,
        address: locationAddress ? locationAddress : null,
      },
      machineType:
        machineTypeName || category
          ? {
              name: machineTypeName ?? '',
              category,
            }
          : null,
      coilItems,
    },
    nextIndex: cursor,
  };
};

const parseCoilItem = (row: SheetRow, globalCategory: string | null): ParsedCoilItemRow => {
  const coilCode = getCellAsString(row, 4);
  const sku = parseSku(getCellAsString(row, 5), globalCategory);

  return {
    coilCode,
    sku,
    current: parseOptionalNumber(row[6]),
    par: parseOptionalNumber(row[7]),
    need: parseOptionalNumber(row[8]),
    forecast: parseOptionalNumber(row[9]),
    total: parseOptionalNumber(row[10]),
    notes: normalizeString(row[11]),
  };
};

const flattenPickEntries = (machines: ParsedRunMachine[]): ParsedPickEntry[] => {
  return machines.flatMap((machine) =>
    machine.coilItems
      .filter((coilItem) => {
        const count = coilItem.total ?? null;
        return count !== null && count !== 0;
      })
      .map((coilItem) => {
        const machineType: ParsedMachineType | null = machine.machineType
          ? { ...machine.machineType }
          : null;
        const location: ParsedMachineLocation | null = machine.location
          ? { ...machine.location }
          : null;
        const machineSummary: ParsedMachine = {
          code: machine.machineCode,
          name: machine.machineName,
          runDate: machine.runDate,
          machineType,
          location,
        };
        const coil: ParsedCoil = {
          code: coilItem.coilCode,
          machine: machineSummary,
        };
        const coilItemSummary: ParsedCoilItem = {
          sku: { ...coilItem.sku },
          coil,
        };
        return {
          coilItem: coilItemSummary,
          count: coilItem.total ?? null,
          current: coilItem.current ?? null,
          par: coilItem.par ?? null,
          need: coilItem.need ?? null,
          forecast: coilItem.forecast ?? null,
          total: coilItem.total ?? null,
          notes: coilItem.notes ?? null,
        };
      }),
  );
};

const deriveRunDate = (locations: ParsedRunLocation[]): Date | null => {
  const dates = locations
    .map((location) => location.runDate)
    .concat(locations.flatMap((location) => location.machines.map((machine) => machine.runDate)))
    .filter((date): date is Date => date instanceof Date && !Number.isNaN(date.getTime()));

  if (!dates.length) {
    return null;
  }

  const earliest = dates.reduce((min, current) => (current.getTime() < min.getTime() ? current : min));
  return earliest ?? null;
};

const parseSku = (value: string, globalCategory: string | null): ParsedSku => {
  if (!value) {
    return { code: '', name: '', type: null, category: globalCategory };
  }

  const parts = value.split(' - ').map((item) => item.trim()).filter(Boolean);

  if (!parts.length) {
    return { code: '', name: '', type: null, category: globalCategory };
  }

  const [codeSegment, ...others] = parts;
  const code = codeSegment ?? '';

  // Try to get category from the global mapping first
  let category = globalCategory;
  const categoryMap = (global as any).categoryMap as Map<string, string>;
  if (categoryMap && categoryMap.has(code.toLowerCase())) {
    category = categoryMap.get(code.toLowerCase())!;
  }

  if (!others.length) {
    return { code, name: '', type: null, category };
  }

  if (others.length === 1) {
    const [nameOnly] = others;
    return { code, name: nameOnly ?? '', type: null, category };
  }

  const typeCandidate = others[others.length - 1] ?? null;
  const nameSegments = others.slice(0, -1).filter(Boolean);
  const name = nameSegments.length ? nameSegments.join(' - ') : typeCandidate ?? '';
  const type = nameSegments.length ? typeCandidate : null;

  return { code, name, type, category };
};

const parseLocationHeader = (value: string): { locationName: string; runDate: Date | null } => {
  const trimmed = value.replace(LOCATION_PREFIX, '').trim();
  const match = trimmed.match(/^(?<name>.+?)\s*\((?<date>[^)]+)\)$/);

  if (!match || !match.groups) {
    return { locationName: trimmed, runDate: null };
  }

  const locationName = (match.groups.name ?? '').trim();
  const runDateString = match.groups.date ?? '';
  return { locationName, runDate: parseDate(runDateString) };
};

const parseMachineCode = (value: string, locationName: string): string => {
  const [, afterMarker = ''] = value.split(MACHINE_HEADER_MARKER);
  const code = afterMarker.trim();
  if (!code) {
    throw new Error(`Unable to parse machine code for location "${locationName}" from "${value}"`);
  }
  return code;
};

const parseMachineInfo = (
  value: string,
  globalCategory: string | null,
): {
  machineName: string;
  category: string | null;
  machineTypeName: string | null;
  runDate: Date | null;
} => {
  if (!value) {
    return {
      machineName: '',
      category: null,
      machineTypeName: null,
      runDate: null,
    };
  }

  const runDateMatch = value.match(/\((\d{1,2}\/\d{1,2}\/\d{4})\)\s*$/);
  const runDateIndex = runDateMatch && typeof runDateMatch.index === 'number' ? runDateMatch.index : null;
  const runDateString = runDateMatch && runDateMatch[1] ? runDateMatch[1] : null;
  const runDate = runDateString ? parseDate(runDateString) : null;
  let remaining = runDateIndex !== null ? value.slice(0, runDateIndex).trim() : value.trim();

  let machineTypeName: string | null = null;
  const typeMatch = remaining.match(/\(([^)]+)\)\s*$/);
  if (typeMatch && typeof typeMatch.index === 'number') {
    machineTypeName = (typeMatch[1] ?? '').trim();
    remaining = remaining.slice(0, typeMatch.index).trim();
  }

  const [rawName, ...categoryParts] = remaining.split(',').map((part) => part.trim()).filter(Boolean);
  const machineName = rawName ?? '';
  const category = categoryParts.length ? categoryParts.join(', ') : globalCategory;

  return {
    machineName,
    category,
    machineTypeName,
    runDate,
  };
};

const parseDate = (value: string): Date | null => {
  const parts = value.split('/');
  if (parts.length !== 3) {
    return null;
  }
  const dayRaw = parts[0] ?? '';
  const monthRaw = parts[1] ?? '';
  const yearRaw = parts[2] ?? '';
  const day = Number.parseInt(dayRaw, 10);
  const month = Number.parseInt(monthRaw, 10);
  const year = Number.parseInt(yearRaw, 10);
  if (!Number.isFinite(day) || !Number.isFinite(month) || !Number.isFinite(year)) {
    return null;
  }
  const isoString = `${year.toString().padStart(4, '0')}-${month.toString().padStart(2, '0')}-${day
    .toString()
    .padStart(2, '0')}T00:00:00.000Z`;
  const date = new Date(isoString);
  return Number.isNaN(date.getTime()) ? null : date;
};

const parseOptionalNumber = (value: string | number | null | undefined): number | null => {
  if (value === undefined || value === null) {
    return null;
  }

  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  const normalized = String(value).trim();
  if (!normalized || normalized === '-' || normalized.toLowerCase() === 'n/a') {
    return null;
  }

  const parsed = Number(normalized.replace(/,/g, ''));
  return Number.isFinite(parsed) ? parsed : null;
};

const normalizeString = (value: string | number | null | undefined): string | null => {
  if (value === undefined || value === null) {
    return null;
  }
  const normalized = String(value).trim();
  return normalized ? normalized : null;
};

const getCellAsString = (row: SheetRow | undefined, index: number): string => {
  if (!row) {
    return '';
  }
  return normalizeString(row[index]) ?? '';
};

const isRowEmpty = (row: SheetRow | undefined): boolean => {
  if (!row) {
    return true;
  }
  return row.every((cell) => !normalizeString(cell));
};

const isRowMostlyEmpty = (row: SheetRow | undefined): boolean => {
  if (!row) {
    return true;
  }
  const significantCells = row.filter((cell, idx) => idx <= 11).filter((cell) => normalizeString(cell));
  return significantCells.length === 0;
};

const extractCategoryFromSheet = async (worksheet: Worksheet): Promise<string | null> => {
  const rows: SheetRow[] = [];
  worksheet.eachRow((row, rowNumber) => {
    if (rowNumber > 0) { // Skip header row in exceljs
      const rowData: SheetRow = [];
      row.eachCell((cell, colNumber) => {
        rowData[colNumber - 1] = cell.value?.toString() || '';
      });
      // Fill empty cells to maintain consistent row length
      while (rowData.length < worksheet.columnCount) {
        rowData.push('');
      }
      rows.push(rowData);
    }
  });

  if (!rows.length) {
    return null;
  }

  // Look for header row to find column indices
  let headerRow: SheetRow | null = null;
  let headerRowIndex = -1;
  
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const firstCell = getCellAsString(row, 0);
    if (firstCell.toLowerCase().includes('item code') || firstCell.toLowerCase().includes('itemname')) {
      headerRow = row || null;
      headerRowIndex = i;
      break;
    }
  }

  if (!headerRow) {
    return null;
  }

  // Find column indices
  let itemCodeCol = -1;
  let categoryCol = -1;
  
  for (let i = 0; i < headerRow.length; i++) {
    const cell = getCellAsString(headerRow, i).toLowerCase();
    if (cell.includes('item code')) {
      itemCodeCol = i;
    } else if (cell.includes('category')) {
      categoryCol = i;
    }
  }

  if (itemCodeCol === -1 || categoryCol === -1) {
    return null;
  }

  // Create category mapping from all data rows
  const categoryMap = new Map<string, string>();
  
  for (let i = headerRowIndex + 1; i < rows.length; i++) {
    const row = rows[i];
    const itemCode = getCellAsString(row, itemCodeCol);
    const category = getCellAsString(row, categoryCol);
    
    if (itemCode && category) {
      categoryMap.set(itemCode.trim().toLowerCase(), category.trim());
    }
  }

  // Store the mapping globally for use during SKU parsing
  (global as any).categoryMap = categoryMap;
  
  // Return a default category (first one found) for fallback
  const categories = Array.from(categoryMap.values());
  return categories.length > 0 ? (categories[0] || null) : null;
};
