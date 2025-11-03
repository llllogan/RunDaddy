import { Router } from 'express';
import { authenticate } from '../middleware/authenticate.js';
import { runImportUpload, uploadRunWorkbook } from './helpers/run-imports.js';

const router = Router();

router.use(authenticate);

// Imports a run workbook and persists machines, coils, and pick entries.
router.post('/runs', runImportUpload.single('file'), uploadRunWorkbook);

export const runImportsRouter = router;
