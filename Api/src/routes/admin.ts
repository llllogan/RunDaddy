import { Router } from 'express';
import { RunStatus } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { requirePlatformAdmin } from '../middleware/require-platform-admin.js';
import { setLogConfig } from '../middleware/logging.js';
import { PLATFORM_ADMIN_COMPANY_ID } from '../config/platform-admin.js';

const router = Router();

router.use(authenticate, requirePlatformAdmin);

router.get(
  '/companies',
  setLogConfig({ level: 'minimal' }),
  async (_req, res) => {
    const companies = await prisma.company.findMany({
      where: { id: { not: PLATFORM_ADMIN_COMPANY_ID } },
      orderBy: { createdAt: 'desc' },
      include: {
        _count: {
          select: {
            memberships: true,
            runs: true,
          },
        },
      },
    });

    const companyIds = companies.map((company) => company.id);
    const latestRuns = companyIds.length
      ? await prisma.run.groupBy({
          by: ['companyId'],
          where: { companyId: { in: companyIds } },
          _max: {
            scheduledFor: true,
            createdAt: true,
          },
        })
      : [];
    const activeRuns = companyIds.length
      ? await prisma.run.groupBy({
          by: ['companyId'],
          where: {
            companyId: { in: companyIds },
            status: { not: RunStatus.READY },
          },
          _count: { _all: true },
        })
      : [];

    const latestMap = new Map<string, Date | null>();
    for (const run of latestRuns) {
      const date = run._max?.scheduledFor ?? run._max?.createdAt ?? null;
      latestMap.set(run.companyId, date);
    }

    const activeMap = new Map<string, number>();
    for (const active of activeRuns) {
      activeMap.set(active.companyId, active._count._all);
    }

    return res.json(
      companies.map((company) => ({
        id: company.id,
        name: company.name,
        timeZone: company.timeZone,
        createdAt: company.createdAt,
        updatedAt: company.updatedAt,
        memberCount: company._count.memberships,
        runCount: company._count.runs,
        activeRunCount: activeMap.get(company.id) ?? 0,
        lastRunAt: latestMap.get(company.id) ?? null,
      })),
    );
  },
);

router.get(
  '/companies/:companyId',
  setLogConfig({ level: 'minimal' }),
  async (req, res) => {
    const { companyId } = req.params;
    if (!companyId) {
      return res.status(400).json({ error: 'Company id is required' });
    }
    if (companyId === PLATFORM_ADMIN_COMPANY_ID) {
      return res.status(403).json({ error: 'Admin workspace cannot be inspected' });
    }

    const company = await prisma.company.findUnique({
      where: { id: companyId },
      include: {
        memberships: {
          include: {
            user: true,
          },
          orderBy: {
            user: {
              lastName: 'asc',
            },
          },
        },
        runs: {
          orderBy: { scheduledFor: 'desc' },
          take: 5,
          include: {
            picker: {
              select: { id: true, firstName: true, lastName: true },
            },
            runner: {
              select: { id: true, firstName: true, lastName: true },
            },
          },
        },
        _count: {
          select: {
            memberships: true,
            runs: true,
          },
        },
      },
    });

    if (!company) {
      return res.status(404).json({ error: 'Company not found' });
    }

    const activeRunCount = await prisma.run.count({
      where: {
        companyId,
        status: { not: RunStatus.READY },
      },
    });

    return res.json({
      id: company.id,
      name: company.name,
      timeZone: company.timeZone,
      createdAt: company.createdAt,
      updatedAt: company.updatedAt,
      memberCount: company._count.memberships,
      runCount: company._count.runs,
      activeRunCount,
      members: company.memberships.map((membership) => ({
        id: membership.id,
        userId: membership.userId,
        role: membership.role,
        firstName: membership.user.firstName,
        lastName: membership.user.lastName,
        email: membership.user.email,
        phone: membership.user.phone,
        createdAt: membership.user.createdAt,
        updatedAt: membership.user.updatedAt,
      })),
      recentRuns: company.runs.map((run) => ({
        id: run.id,
        status: run.status,
        scheduledFor: run.scheduledFor,
        picker: run.picker
          ? { id: run.picker.id, name: `${run.picker.firstName} ${run.picker.lastName}` }
          : null,
        runner: run.runner
          ? { id: run.runner.id, name: `${run.runner.firstName} ${run.runner.lastName}` }
          : null,
      })),
    });
  },
);

export const adminRouter = router;
