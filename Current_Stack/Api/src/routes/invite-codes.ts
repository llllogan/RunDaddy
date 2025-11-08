import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { createTokenPair } from '../lib/tokens.js';
import { buildSessionPayload, respondWithSession } from './helpers/auth.js';
import { AuthContext } from '../types/enums.js';

const router = Router();

// Validate and use invite code
router.post('/use', authenticate, async (req, res) => {
  try {
  const { code } = req.body;
  const userId = req.auth!.userId;
  const context = req.auth?.context ?? AuthContext.APP;

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
          select: { id: true, name: true }
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

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        phone: true,
        role: true,
        defaultMembershipId: true,
      },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (!user.defaultMembershipId) {
      await prisma.user.update({
        where: { id: userId },
        data: { defaultMembershipId: membership.id }
      });
    }

    const companySummary = { id: membership.company.id, name: membership.company.name };
    const tokens = createTokenPair({
      userId: user.id,
      companyId: membership.companyId,
      email: user.email,
      role: membership.role,
      context,
    });

    await prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenId: tokens.refreshTokenId,
        expiresAt: tokens.refreshTokenExpiresAt,
        context: tokens.context,
      },
    });

    const membershipPayload = {
      id: membership.id,
      userId: membership.userId,
      companyId: membership.companyId,
      role: membership.role,
      company: { id: membership.company.id, name: membership.company.name },
    };

    return respondWithSession(
      res,
      buildSessionPayload(
        {
          id: user.id,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          role: membership.role,
          phone: user.phone,
        },
        companySummary,
        tokens,
      ),
      200,
      {
        message: 'Successfully joined company',
        membership: membershipPayload,
      },
    );
  } catch (error) {
    console.error('Error using invite code:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export const inviteCodesRouter = router;
