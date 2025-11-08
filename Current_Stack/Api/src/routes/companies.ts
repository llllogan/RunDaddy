import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from './helpers/authorization.js';
import { randomBytes } from 'crypto';

const router = Router();

// Generate invite code for a company
router.post('/:companyId/invite-codes', authenticate, async (req, res) => {
  try {
    const { companyId } = req.params;
    const { role } = req.body;
    const userId = req.auth!.userId;

    if (!role) {
      return res.status(400).json({ error: 'Role is required' });
    }

    // Verify user is admin/owner of this specific company
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

// Get active invite codes for a company
router.get('/:companyId/invite-codes', authenticate, async (req, res) => {
  try {
    const { companyId } = req.params;
    const userId = req.auth!.userId;

    // Verify user is admin/owner of this specific company
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

// Leave a company
router.post('/:companyId/leave', authenticate, async (req, res) => {
  try {
    const { companyId } = req.params;
    const userId = req.auth!.userId;

    // Find the membership to delete
    const membership = await prisma.membership.findFirst({
      where: {
        userId,
        companyId
      }
    });

    if (!membership) {
      return res.status(404).json({ error: 'Membership not found' });
    }

    // Delete the membership
    await prisma.membership.delete({
      where: {
        id: membership.id
      }
    });

    // Update user's default membership if it was pointing to this membership
    const user = await prisma.user.findUnique({
      where: { id: userId }
    });

    if (user?.defaultMembershipId === membership.id) {
      // Find another membership to set as default, or clear it
      const anotherMembership = await prisma.membership.findFirst({
        where: {
          userId,
          id: { not: membership.id }
        }
      });

      await prisma.user.update({
        where: { id: userId },
        data: { 
          defaultMembershipId: anotherMembership?.id || null 
        }
      });
    }

    res.json({ message: 'Successfully left company' });
  } catch (error) {
    console.error('Error leaving company:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Remove a member from a company (for admins/owners)
router.delete('/:companyId/members/:userId', authenticate, async (req, res) => {
  try {
    const { companyId, userId: targetUserId } = req.params;
    const currentUserId = req.auth!.userId;

    // Verify the current user is admin/owner of this specific company
    const adminMembership = await prisma.membership.findFirst({
      where: {
        userId: currentUserId,
        companyId,
        role: { in: ['ADMIN', 'OWNER'] }
      }
    });

    if (!adminMembership) {
      return res.status(403).json({ error: 'Not authorized to remove members from this company' });
    }

    // Find the membership to delete
    const membership = await prisma.membership.findFirst({
      where: {
        userId: targetUserId,
        companyId
      }
    });

    if (!membership) {
      return res.status(404).json({ error: 'Membership not found' });
    }

    // Don't allow removing the last owner
    if (membership.role === 'OWNER') {
      const ownerCount = await prisma.membership.count({
        where: {
          companyId,
          role: 'OWNER'
        }
      });

      if (ownerCount <= 1) {
        return res.status(400).json({ error: 'Cannot remove the last owner from a company' });
      }
    }

    // Delete the membership
    await prisma.membership.delete({
      where: {
        id: membership.id
      }
    });

    // Update user's default membership if it was pointing to this membership
    const user = await prisma.user.findUnique({
      where: { id: targetUserId }
    });

    if (user?.defaultMembershipId === membership.id) {
      // Find another membership to set as default, or clear it
      const anotherMembership = await prisma.membership.findFirst({
        where: {
          userId: targetUserId,
          id: { not: membership.id }
        }
      });

      await prisma.user.update({
        where: { id: targetUserId },
        data: { 
          defaultMembershipId: anotherMembership?.id || null 
        }
      });
    }

    res.json({ message: 'Successfully removed member from company' });
  } catch (error) {
    console.error('Error removing member:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export const companyRouter = router;