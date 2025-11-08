import { Router } from 'express';
import { authenticate } from '../middleware/authenticate.js';
import { runImportUpload, uploadRunWorkbook } from './helpers/run-imports.js';

const router = Router();

router.use(authenticate);

// Imports a run workbook and persists machines, coils, and pick entries.
router.post('/runs', (req, res, next) => {
  // Check if user has company before proceeding
  if (!req.auth?.companyId) {
    return res.status(403).json({ error: 'Company membership required to import runs' });
  }
  next();
}, runImportUpload.single('file'), uploadRunWorkbook);

export const runImportsRouter = router;
