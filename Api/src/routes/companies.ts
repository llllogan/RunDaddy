import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { authorize } from './helpers/authorization.js';
import { randomBytes } from 'crypto';
import { createTokenPair } from '../lib/tokens.js';
import { buildSessionPayload, respondWithSession } from './helpers/auth.js';
import { AuthContext, UserRole } from '../types/enums.js';
import { userHasPlatformAdminAccess } from '../lib/platform-admin.js';
import { PLATFORM_ADMIN_COMPANY_ID } from '../config/platform-admin.js';
import { isValidTimezone } from '../lib/timezone.js';
import { getCompanyTierWithCounts, remainingCapacityForRole } from './helpers/company-tier.js';

const router = Router();

router.get('/:companyId/features', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { companyId } = req.params;
  if (!companyId) {
    return res.status(400).json({ error: 'Company ID is required' });
  }

  const membership = await prisma.membership.findUnique({
    where: {
      userId_companyId: {
        userId: req.auth.userId!,
        companyId,
      },
    },
  });

  if (!membership) {
    return res
      .status(403)
      .json({ error: 'Membership required to access company features' });
  }

  const tierInfo = await getCompanyTierWithCounts(companyId);

  if (!tierInfo) {
    return res.status(404).json({ error: 'Company not found' });
  }

  const { company, tier, membershipCounts } = tierInfo;

  return res.json({
    companyId: company.id,
    tier: {
      id: tier.id,
      name: tier.name,
      maxOwners: tier.maxOwners,
      maxAdmins: tier.maxAdmins,
      maxPickers: tier.maxPickers,
      canBreakDownRun: tier.canBreakDownRun,
    },
    features: {
      canBreakDownRun: tier.canBreakDownRun,
    },
    membershipCounts,
    remainingCapacity: {
      owners: Math.max(tier.maxOwners - membershipCounts.owners, 0),
      admins: Math.max(tier.maxAdmins - membershipCounts.admins, 0),
      pickers: Math.max(tier.maxPickers - membershipCounts.pickers, 0),
    },
  });
});

// Generate invite code for a company
router.post('/:companyId/invite-codes', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  try {
    const { companyId } = req.params;
    const { role } = req.body;
    const userId = req.auth!.userId;

    if (!role) {
      return res.status(400).json({ error: 'Role is required' });
    }

    const normalizedRole = (role as string).toUpperCase() as UserRole;

    if (normalizedRole === UserRole.GOD && companyId !== PLATFORM_ADMIN_COMPANY_ID) {
      return res.status(403).json({ error: 'Only the platform admin workspace can create GOD invites' });
    }

    // Verify user is admin/owner of this specific company
    const membership = await prisma.membership.findFirst({
      where: {
        userId,
        companyId: companyId!,
        role: { in: ['GOD', 'ADMIN', 'OWNER'] }
      }
    });

    if (!membership) {
      return res.status(403).json({ error: 'Not authorized to create invites for this company' });
    }

    const tierInfo = await getCompanyTierWithCounts(companyId!);
    if (!tierInfo) {
      return res.status(404).json({ error: 'Company not found' });
    }

    const capacity = remainingCapacityForRole(tierInfo.tier, tierInfo.membershipCounts, normalizedRole);
    if (!capacity.allowed) {
      return res.status(409).json({
        error: 'Plan limit reached',
        detail: `${normalizedRole} slots are full for this plan.`,
      });
    }

    // Generate unique code
    const code = randomBytes(32).toString('hex').toUpperCase();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes from now

    const inviteCode = await prisma.inviteCode.create({
      data: {
        code,
        companyId: companyId!,
        role: normalizedRole,
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
router.get('/:companyId/invite-codes', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  try {
    const { companyId } = req.params;
    const userId = req.auth!.userId;

    // Verify user is admin/owner of this specific company
    const membership = await prisma.membership.findFirst({
      where: {
        userId,
        companyId: companyId!,
        role: { in: ['GOD', 'ADMIN', 'OWNER'] }
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
router.post('/:companyId/leave', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  try {
    const { companyId } = req.params;
    const userId = req.auth!.userId;
    const context = req.auth?.context ?? AuthContext.WEB;

    // Find the membership to delete
    const membership = await prisma.membership.findFirst({
      where: {
        userId,
        companyId: companyId!
      }
    });

    if (!membership) {
      return res.status(404).json({ error: 'Membership not found' });
    }

    const user = await prisma.user.findUnique({
      where: { id: userId! },
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

    // Delete the membership
    await prisma.membership.delete({
      where: {
        id: membership.id
      }
    });

    const remainingMemberships = await prisma.membership.findMany({
      where: {
        userId: userId!,
      },
      include: {
        company: {
          select: {
            id: true,
            name: true,
            location: true,
            timeZone: true,
          },
        },
      },
    });

    const defaultStillValid =
      !!(user.defaultMembershipId && remainingMemberships.some((m) => m.id === user.defaultMembershipId));

    let nextDefaultMembershipId = user.defaultMembershipId ?? null;
    if (!defaultStillValid) {
      nextDefaultMembershipId = remainingMemberships[0]?.id ?? null;
      if (nextDefaultMembershipId !== user.defaultMembershipId) {
        await prisma.user.update({
          where: { id: userId! },
          data: { defaultMembershipId: nextDefaultMembershipId },
        });
      }
    }

    const activeMembership =
      (nextDefaultMembershipId
        ? remainingMemberships.find((m) => m.id === nextDefaultMembershipId)
        : remainingMemberships[0]) ?? null;

    const companySummary = activeMembership
      ? { id: activeMembership.company.id, name: activeMembership.company.name }
      : null;
    const sessionRole = activeMembership?.role ?? user.role;

    const tokens = createTokenPair({
      userId: user.id,
      companyId: companySummary?.id ?? null,
      email: user.email,
      role: sessionRole,
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

    const membershipPayload = activeMembership
      ? {
          id: activeMembership.id,
          userId: activeMembership.userId,
          companyId: activeMembership.companyId,
          role: activeMembership.role,
          company: {
            id: activeMembership.company.id,
            name: activeMembership.company.name,
            location: activeMembership.company.location ?? null,
            timeZone: activeMembership.company.timeZone ?? null,
          },
        }
      : null;

    const platformAdmin = await userHasPlatformAdminAccess(user.id);
    const platformAdminCompanyId = platformAdmin ? PLATFORM_ADMIN_COMPANY_ID : null;

    return respondWithSession(
      res,
      buildSessionPayload(
        {
          id: user.id,
          email: user.email,
          firstName: user.firstName,
          lastName: user.lastName,
          role: sessionRole,
          phone: user.phone,
          platformAdmin,
        },
        companySummary,
        tokens,
        platformAdminCompanyId,
      ),
      200,
      {
        message: 'Successfully left company',
        membership: membershipPayload,
      },
    );
  } catch (error) {
    console.error('Error leaving company:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Remove a member from a company (for admins/owners)
router.delete('/:companyId/members/:userId', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  try {
    const { companyId, userId: targetUserId } = req.params;
    const currentUserId = req.auth!.userId;

    // Verify the current user is admin/owner of this specific company
    const adminMembership = await prisma.membership.findFirst({
      where: {
        userId: currentUserId,
        companyId: companyId!,
        role: { in: ['GOD', 'ADMIN', 'OWNER'] }
      }
    });

    if (!adminMembership) {
      return res.status(403).json({ error: 'Not authorized to remove members from this company' });
    }

    // Find the membership to delete
    const membership = await prisma.membership.findFirst({
      where: {
        userId: targetUserId!,
        companyId: companyId!
      }
    });

    if (!membership) {
      return res.status(404).json({ error: 'Membership not found' });
    }

    // Don't allow removing the last owner
    if (membership.role === 'OWNER') {
      const ownerCount = await prisma.membership.count({
        where: {
          companyId: companyId!,
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
      where: { id: targetUserId! }
    });

    if (user?.defaultMembershipId === membership.id) {
      // Find another membership to set as default, or clear it
      const anotherMembership = await prisma.membership.findFirst({
        where: {
          userId: targetUserId!,
          id: { not: membership.id }
        }
      });

      await prisma.user.update({
        where: { id: targetUserId! },
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

router.patch('/:companyId/timezone', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  const { companyId } = req.params;
  const { timeZone } = req.body ?? {};

  if (!companyId) {
    return res.status(400).json({ error: 'companyId is required' });
  }

  if (!timeZone || typeof timeZone !== 'string' || !isValidTimezone(timeZone)) {
    return res.status(400).json({ error: 'Invalid timezone' });
  }

  const membership = await prisma.membership.findFirst({
    where: {
      userId: req.auth!.userId,
      companyId,
      role: { in: ['GOD', 'ADMIN', 'OWNER'] },
    },
    include: {
      company: true,
    },
  });

  if (!membership) {
    return res.status(403).json({ error: 'Not authorized to update this company' });
  }

  try {
    const updated = await prisma.company.update({
      where: { id: companyId },
      data: { timeZone },
    });

    return res.json({
      company: {
        id: updated.id,
        name: updated.name,
        role: membership.role,
        location: updated.location ?? null,
        timeZone: updated.timeZone ?? null,
      },
    });
  } catch (error) {
    console.error('Error updating company timezone:', error);
    return res.status(500).json({ error: 'Unable to update company timezone' });
  }
});

router.patch('/:companyId/location', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  const { companyId } = req.params;
  const { location } = req.body ?? {};

  if (!companyId) {
    return res.status(400).json({ error: 'companyId is required' });
  }

  if (location !== undefined && location !== null && typeof location !== 'string') {
    return res.status(400).json({ error: 'Invalid location' });
  }

  const normalizedLocation = typeof location === 'string' ? location.trim() : null;
  if (normalizedLocation && normalizedLocation.length < 3) {
    return res.status(400).json({ error: 'Location must be at least 3 characters' });
  }

  const membership = await prisma.membership.findFirst({
    where: {
      userId: req.auth!.userId,
      companyId,
      role: { in: ['GOD', 'ADMIN', 'OWNER'] },
    },
    include: {
      company: true,
    },
  });

  if (!membership) {
    return res.status(403).json({ error: 'Not authorized to update this company' });
  }

  try {
    const updated = await prisma.company.update({
      where: { id: companyId },
      data: { location: normalizedLocation && normalizedLocation.length > 0 ? normalizedLocation : null },
    });

    return res.json({
      company: {
        id: updated.id,
        name: updated.name,
        role: membership.role,
        location: updated.location ?? null,
        timeZone: updated.timeZone ?? null,
      },
    });
  } catch (error) {
    console.error('Error updating company location:', error);
    return res.status(500).json({ error: 'Unable to update company location' });
  }
});

export const companyRouter = router;
