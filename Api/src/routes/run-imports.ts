import { Router } from 'express';
import multer from 'multer';
import { uploadRunWorkbook } from '../controllers/run-import.controller.js';

const router = Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB
  },
});

router.post('/runs', upload.single('file'), uploadRunWorkbook);

export const runImportsRouter = router;
