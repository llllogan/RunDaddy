import { AccountRole } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { hashPassword } from '../lib/password.js';

const DEFAULT_SEED_PASSWORD = process.env.SEED_USER_PASSWORD ?? 'SeedDataPass!123';

const LIGHTHOUSE_USER = {
  email: 'lighthouse@admin.com',
  firstName: 'Lighthouse',
  lastName: 'Admin',
  phone: '555-0505',
};

async function upsertLighthouseAdmin() {
  const hashedPassword = await hashPassword(DEFAULT_SEED_PASSWORD);

  await prisma.user.upsert({
    where: { email: LIGHTHOUSE_USER.email },
    update: {
      firstName: LIGHTHOUSE_USER.firstName,
      lastName: LIGHTHOUSE_USER.lastName,
      phone: LIGHTHOUSE_USER.phone,
      password: hashedPassword,
      role: AccountRole.LIGHTHOUSE,
    },
    create: {
      email: LIGHTHOUSE_USER.email,
      firstName: LIGHTHOUSE_USER.firstName,
      lastName: LIGHTHOUSE_USER.lastName,
      phone: LIGHTHOUSE_USER.phone,
      password: hashedPassword,
      role: AccountRole.LIGHTHOUSE,
    },
  });

  console.log('Lighthouse admin seeded:', LIGHTHOUSE_USER.email);
}

async function main() {
  await upsertLighthouseAdmin();
}

main()
  .catch((error) => {
    console.error('Failed to seed lighthouse admin:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
