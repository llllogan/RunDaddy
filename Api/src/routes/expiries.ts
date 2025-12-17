import { Router } from 'express';
import { z } from 'zod';
import { authenticate } from '../middleware/authenticate.js';
import { requireCompanyContext } from '../middleware/requireCompany.js';
import { setLogConfig } from '../middleware/logging.js';
import { buildUpcomingExpiringItems } from './helpers/expiring-items.js';

const router = Router();

router.use(authenticate, requireCompanyContext());

const upcomingQuerySchema = z.object({
  daysAhead: z.coerce.number().int().min(0).max(28).optional(),
});

router.get('/', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const parsedQuery = upcomingQuerySchema.safeParse(req.query);
  if (!parsedQuery.success) {
    return res.status(400).json({ error: 'Invalid filters supplied', details: parsedQuery.error.flatten() });
  }

  const companyId = req.auth.companyId as string;
  const response = await buildUpcomingExpiringItems({
    companyId,
    daysAhead: parsedQuery.data.daysAhead ?? 14,
  });

  return res.json(response);
});

export { router as expiriesRouter };
