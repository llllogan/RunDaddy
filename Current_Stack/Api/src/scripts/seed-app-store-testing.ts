import { RunStatus, UserRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { hashPassword } from '../lib/password.js';

const APP_STORE_COMPANY_NAME = 'Apple';
const APP_STORE_TEST_EMAIL = process.env.APP_STORE_TEST_EMAIL ?? 'appstore-testing@apple.com';
const APP_STORE_TEST_PASSWORD = process.env.APP_STORE_TEST_PASSWORD ?? 'AppleTestingOnly!123';

const startOfToday = () => {
  const now = new Date();
  now.setHours(0, 0, 0, 0);
  return now;
};

const endOfToday = () => {
  const tomorrow = startOfToday();
  tomorrow.setDate(tomorrow.getDate() + 1);
  return tomorrow;
};

async function ensureTestingCompany() {
  const existing = await prisma.company.findFirst({
    where: { name: APP_STORE_COMPANY_NAME },
  });

  if (existing) {
    return existing;
  }

  return prisma.company.create({
    data: {
      name: APP_STORE_COMPANY_NAME,
    },
  });
}

async function upsertTestingUser(companyId: string) {
  const hashedPassword = await hashPassword(APP_STORE_TEST_PASSWORD);
  const testingProfile = {
    firstName: 'App Store',
    lastName: 'Testing Account',
    role: UserRole.ADMIN,
    phone: 'TESTING-APPLE',
    password: hashedPassword,
  };

  const user = await prisma.user.upsert({
    where: { email: APP_STORE_TEST_EMAIL },
    update: testingProfile,
    create: {
      ...testingProfile,
      email: APP_STORE_TEST_EMAIL,
      memberships: {
        create: {
          companyId,
          role: UserRole.ADMIN,
        },
      },
    },
  });

  return prisma.user.findUniqueOrThrow({
    where: { id: user.id },
    include: { memberships: true },
  });
}

async function ensureMembership(userId: string, companyId: string) {
  const membership = await prisma.membership.findFirst({
    where: { userId, companyId },
  });

  if (membership) {
    if (membership.role !== UserRole.ADMIN) {
      return prisma.membership.update({
        where: { id: membership.id },
        data: { role: UserRole.ADMIN },
      });
    }
    return membership;
  }

  return prisma.membership.create({
    data: {
      userId,
      companyId,
      role: UserRole.ADMIN,
    },
  });
}

async function ensureTodaysRun(companyId: string, pickerId: string) {
  const existing = await prisma.run.findFirst({
    where: {
      companyId,
      scheduledFor: {
        gte: startOfToday(),
        lt: endOfToday(),
      },
    },
    orderBy: { scheduledFor: 'asc' },
  });

  if (existing) {
    if (existing.pickerId !== pickerId) {
      return prisma.run.update({
        where: { id: existing.id },
        data: { pickerId },
      });
    }
    return existing;
  }

  return prisma.run.create({
    data: {
      companyId,
      status: RunStatus.CREATED,
      scheduledFor: new Date(),
      pickerId,
    },
  });
}

async function main() {
  console.log('Creating Apple testing workspace...');
  const company = await ensureTestingCompany();

  const user = await upsertTestingUser(company.id);
  let membership = user.memberships.find((member) => member.companyId === company.id);
  if (!membership) {
    membership = await ensureMembership(user.id, company.id);
  }

  if (user.defaultMembershipId !== membership.id) {
    await prisma.user.update({
      where: { id: user.id },
      data: { defaultMembershipId: membership.id },
    });
  }

  const run = await ensureTodaysRun(company.id, user.id);

  console.log('Apple testing company id:', company.id);
  console.log('Testing admin email:', APP_STORE_TEST_EMAIL);
  console.log('Testing admin password (plaintext):', APP_STORE_TEST_PASSWORD);
  console.log('Today run id:', run.id, 'scheduled for', run.scheduledFor?.toISOString());
}

main()
  .then(() => {
    console.log('Apple testing seed completed.');
  })
  .catch((error) => {
    console.error('Failed to seed Apple testing data:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
