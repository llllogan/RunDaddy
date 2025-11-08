import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from './helpers/authorization.js';
import { randomBytes } from 'crypto';

const router = Router();

// Generate invite code
router.post('/generate', authenticate, authorize(['ADMIN', 'OWNER']), async (req, res) => {
  try {
  const { role, companyId } = req.body;
  const userId = req.auth!.userId;

    if (!role || !companyId) {
      return res.status(400).json({ error: 'Role and companyId are required' });
    }

    // Verify user is admin/owner of this company
    const membership = await prisma.membership.findFirst({
      where: {
        userId,
        companyId,
        role: { in: ['ADMIN', 'OWNER'] }
      }
    });

    if (!membership) {
      return res.status(403).json({ error: 'Not authorized to create invites for this company' });
    }

    // Generate unique code
    const code = randomBytes(32).toString('hex').toUpperCase();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes from now

    const inviteCode = await prisma.inviteCode.create({
      data: {
        code,
        companyId,
        role,
        createdBy: userId,
        expiresAt
      },
      include: {
        company: {
          select: { name: true }
        },
        creator: {
          select: { firstName: true, lastName: true }
        }
      }
    });

    res.json(inviteCode);
  } catch (error) {
    console.error('Error generating invite code:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Validate and use invite code
router.post('/use', authenticate, async (req, res) => {
  try {
  const { code } = req.body;
  const userId = req.auth!.userId;

    if (!code) {
      return res.status(400).json({ error: 'Invite code is required' });
    }

    // Find valid invite code
    const inviteCode = await prisma.inviteCode.findFirst({
      where: {
        code: code.toUpperCase(),
        usedBy: null,
        expiresAt: { gt: new Date() }
      },
      include: {
        company: true
      }
    });

    if (!inviteCode) {
      return res.status(400).json({ error: 'Invalid or expired invite code' });
    }

    // Check if user is already a member of this company
    const existingMembership = await prisma.membership.findFirst({
      where: {
        userId,
        companyId: inviteCode.companyId
      }
    });

    if (existingMembership) {
      return res.status(400).json({ error: 'Already a member of this company' });
    }

    // Create membership
    const membership = await prisma.membership.create({
      data: {
        userId,
        companyId: inviteCode.companyId,
        role: inviteCode.role
      },
      include: {
        company: {
          select: { name: true }
        }
      }
    });

    // Mark invite code as used
    await prisma.inviteCode.update({
      where: { id: inviteCode.id },
      data: {
        usedBy: userId,
        usedAt: new Date()
      }
    });

    // Update user's default membership if they don't have one
    const user = await prisma.user.findUnique({
      where: { id: userId }
    });

    if (!user?.defaultMembershipId) {
      await prisma.user.update({
        where: { id: userId },
        data: { defaultMembershipId: membership.id }
      });
    }

    res.json({
      message: 'Successfully joined company',
      membership
    });
  } catch (error) {
    console.error('Error using invite code:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get active invite codes for a company
router.get('/company/:companyId', authenticate, authorize(['ADMIN', 'OWNER']), async (req, res) => {
  try {
    const { companyId } = req.params;
    const userId = req.auth!.userId;

    // Verify user is admin/owner of this company
    const membership = await prisma.membership.findFirst({
      where: {
        userId,
        companyId: companyId!,
        role: { in: ['ADMIN', 'OWNER'] }
      }
    });

    if (!membership) {
      return res.status(403).json({ error: 'Not authorized to view invites for this company' });
    }

    const inviteCodes = await prisma.inviteCode.findMany({
      where: {
        companyId: companyId!,
        expiresAt: { gt: new Date() }
      },
      include: {
        creator: {
          select: { firstName: true, lastName: true }
        },
        usedByUser: {
          select: { firstName: true, lastName: true }
        }
      },
      orderBy: { createdAt: 'desc' }
    });

    res.json(inviteCodes);
  } catch (error) {
    console.error('Error fetching invite codes:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export const inviteCodesRouter = router;