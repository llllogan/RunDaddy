import type { Request, Response } from 'express';
import { parseRunWorkbook } from '../lib/run-import-parser.js';

export const uploadRunWorkbook = async (req: Request, res: Response) => {
  if (!req.file) {
    return res.status(400).json({ error: 'Missing Excel file payload' });
  }

  try {
    const workbook = parseRunWorkbook(req.file.buffer);

    console.log('--- Parsed Run Workbook ---');
    console.dir(workbook, { depth: null });

    const run = workbook.run;
    const pickEntryCount = run ? run.pickEntries.length : 0;
    const machineCount =
      run && pickEntryCount
        ? new Set(run.pickEntries.map((entry) => entry.coilItem.coil.machine.code)).size
        : 0;

    return res.json({
      summary: {
        runs: run ? 1 : 0,
        machines: machineCount,
        pickEntries: pickEntryCount,
      },
      workbook,
    });
  } catch (error) {
    return res.status(400).json({
      error: 'Unable to parse workbook',
      detail: (error as Error).message,
    });
  }
};
