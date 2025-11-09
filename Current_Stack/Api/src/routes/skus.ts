import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { isCompanyManager } from './helpers/authorization.js';

const router = Router();

router.use(authenticate);

// Update SKU isCheeseAndCrackers field
router.patch('/:skuId/cheese-and-crackers', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  const { isCheeseAndCrackers } = req.body;
  if (typeof isCheeseAndCrackers !== 'boolean') {
    return res.status(400).json({ error: 'isCheeseAndCrackers must be a boolean' });
  }

  // Find the SKU to ensure it exists and get company info
  const sku = await prisma.sKU.findFirst({
    where: {
      id: skuId,
    },
    include: {
      coilItems: {
        include: {
          coil: {
            include: {
              machine: {
                include: {
                  company: true,
                },
              },
            },
          },
        },
      },
    },
  });

  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }

  // Check if the SKU belongs to the user's company through any coil item
  const belongsToCompany = sku.coilItems.some(coilItem => 
    coilItem.coil.machine?.companyId === req.auth!.companyId
  );

  if (!belongsToCompany) {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  // Only managers can update SKU fields
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKU' });
  }

  const updatedSku = await prisma.sKU.update({
    where: { id: skuId },
    data: { isCheeseAndCrackers },
  });

  return res.json({
    id: updatedSku.id,
    code: updatedSku.code,
    name: updatedSku.name,
    type: updatedSku.type,
    isCheeseAndCrackers: updatedSku.isCheeseAndCrackers,
  });
});

// Update SKU countNeededPointer field
router.patch('/:skuId/count-pointer', setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { skuId } = req.params;
  if (!skuId) {
    return res.status(400).json({ error: 'SKU ID is required' });
  }

  const { countNeededPointer } = req.body;
  if (!countNeededPointer || typeof countNeededPointer !== 'string') {
    return res.status(400).json({ error: 'countNeededPointer must be a string' });
  }

  const validPointers = ['current', 'par', 'need', 'forecast', 'total'];
  if (!validPointers.includes(countNeededPointer.toLowerCase())) {
    return res.status(400).json({ error: 'countNeededPointer must be one of: current, par, need, forecast, total' });
  }

  // Find the SKU to ensure it exists and get company info
  const sku = await prisma.sKU.findFirst({
    where: {
      id: skuId,
    },
    include: {
      coilItems: {
        include: {
          coil: {
            include: {
              machine: {
                include: {
                  company: true,
                },
              },
            },
          },
        },
      },
    },
  });

  if (!sku) {
    return res.status(404).json({ error: 'SKU not found' });
  }

  // Check if the SKU belongs to the user's company through any coil item
  const belongsToCompany = sku.coilItems.some(coilItem => 
    coilItem.coil.machine?.companyId === req.auth!.companyId
  );

  if (!belongsToCompany) {
    return res.status(403).json({ error: 'SKU does not belong to your company' });
  }

  // Only managers can update SKU fields
  if (!isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Insufficient permissions to update SKU' });
  }

  const updatedSku = await prisma.sKU.update({
    where: { id: skuId },
    data: { countNeededPointer: countNeededPointer.toLowerCase() },
  });

  return res.json({
    id: updatedSku.id,
    code: updatedSku.code,
    name: updatedSku.name,
    type: updatedSku.type,
    countNeededPointer: updatedSku.countNeededPointer,
  });
});

export const skuRouter = router;