import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';

const router = Router();

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

export const inviteCodesRouter = router;