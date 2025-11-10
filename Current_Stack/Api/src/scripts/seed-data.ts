import { RunItemStatus, RunStatus, UserRole } from '@prisma/client';
import type { Location, MachineType, SKU } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { hashPassword } from '../lib/password.js';

const APP_STORE_COMPANY_NAME = 'Apple';
const APP_STORE_TEST_EMAIL = process.env.APP_STORE_TEST_EMAIL ?? 'appstore-testing@apple.com';
const APP_STORE_TEST_PASSWORD = process.env.APP_STORE_TEST_PASSWORD ?? 'AppleTestingOnly!123';
const DEFAULT_SEED_PASSWORD = process.env.SEED_USER_PASSWORD ?? 'SeedDataPass!123';

const MACHINE_TYPE_SEED_DATA = [
  { name: 'Snack Tower', description: 'Standard snack vending tower' },
  { name: 'Cold Beverage Cooler', description: 'Refrigerated drink merchandiser' },
];

const DEFAULT_MACHINE_TYPE_NAME = MACHINE_TYPE_SEED_DATA[0].name;

const SKU_SEED_DATA = [
  { code: 'SKU-PBAR-ALM', name: 'Almond Protein Bar', type: 'snack', category: 'Protein Bars' },
  { code: 'SKU-CHIPS-SEA', name: 'Sea Salt Chips', type: 'snack', category: 'Chips' },
  { code: 'SKU-COFF-COLD', name: 'Nitro Cold Brew', type: 'beverage', category: 'Coffee' },
  { code: 'SKU-JUICE-CIT', name: 'Citrus Sparkling Juice', type: 'beverage', category: 'Juice' },
  { code: 'SKU-ENERGY-MIX', name: 'Energy Trail Mix', type: 'snack', category: 'Trail Mix' },
  { code: 'SKU-TEA-HERBAL', name: 'Iced Herbal Tea', type: 'beverage', category: 'Tea' },
];

type CoilSeedConfig = {
  code: string;
  skuCode: string;
  par: number;
};

type MachineSeedConfig = {
  code: string;
  description?: string;
  machineType?: string;
  coils: CoilSeedConfig[];
};

type LocationSeedConfig = {
  name: string;
  address?: string;
  machines?: MachineSeedConfig[];
};

type LocationSeedResult = {
  location: Location;
  coilItems: CoilItemSeedInfo[];
};

type CompanySeedConfig = {
  name: string;
  timeZone: string;
  owner: {
    firstName: string;
    lastName: string;
    email: string;
    phone?: string;
  };
  locations: LocationSeedConfig[];
};

const APPLE_LOCATION_CONFIG: LocationSeedConfig[] = [
  {
    name: 'Apple Park Testing Lab',
    address: '1 Apple Park Way, Cupertino, CA',
    machines: [
      {
        code: 'APPLE-SNACK-1',
        description: 'Testing snack machine',
        machineType: 'Snack Tower',
        coils: [
          { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 12 },
          { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 16 },
          { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 14 },
        ],
      },
    ],
  },
];

const COMPANY_SEED_CONFIG: CompanySeedConfig[] = [
  {
    name: 'Metro Snacks Co.',
    timeZone: 'America/Los_Angeles',
    owner: {
      firstName: 'Taylor',
      lastName: 'Kent',
      email: 'taylor.kent+seed@rundaddy.test',
      phone: '555-0101',
    },
    locations: [
      {
        name: 'Metro Warehouse',
        address: '100 Market St, San Francisco, CA',
        machines: [
          {
            code: 'METRO-WH-01',
            description: 'Warehouse Snack Tower',
            machineType: 'Snack Tower',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 18 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 15 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 20 },
            ],
          },
        ],
      },
      {
        name: 'Downtown Drop Off',
        address: '455 Pine St, San Francisco, CA',
        machines: [
          {
            code: 'METRO-DT-01',
            description: 'Downtown Beverage Cooler',
            machineType: 'Cold Beverage Cooler',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 12 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 10 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 14 },
            ],
          },
        ],
      },
    ],
  },
  {
    name: 'River City Logistics',
    timeZone: 'America/Denver',
    owner: {
      firstName: 'Jordan',
      lastName: 'Blake',
      email: 'jordan.blake+seed@rundaddy.test',
      phone: '555-0202',
    },
    locations: [
      {
        name: 'River City HQ',
        address: '200 River Rd, Denver, CO',
        machines: [
          {
            code: 'RIVER-HQ-01',
            description: 'HQ Snack Tower',
            machineType: 'Snack Tower',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 16 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 14 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 18 },
            ],
          },
        ],
      },
      {
        name: 'Aurora Route',
        address: '15 Main St, Aurora, CO',
        machines: [
          {
            code: 'RIVER-AU-01',
            description: 'Aurora Beverage Cooler',
            machineType: 'Cold Beverage Cooler',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 10 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 12 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 11 },
            ],
          },
        ],
      },
    ],
  },
];

const EXTRA_USERS = [
  {
    firstName: 'Casey',
    lastName: 'Nguyen',
    email: 'casey.nguyen+seed@rundaddy.test',
    phone: '555-0303',
  },
  {
    firstName: 'Skyler',
    lastName: 'Lopez',
    email: 'skyler.lopez+seed@rundaddy.test',
    phone: '555-0404',
  },
];

const machineTypeCache = new Map<string, MachineType>();
const skuCache = new Map<string, SKU>();

type CoilItemSeedInfo = {
  id: string;
  par: number;
};

async function ensureMachineTypeByName(name: string, description?: string) {
  const cached = machineTypeCache.get(name);
  if (cached) {
    if (description && cached.description !== description) {
      const updated = await prisma.machineType.update({
        where: { id: cached.id },
        data: { description },
      });
      machineTypeCache.set(name, updated);
      return updated;
    }
    return cached;
  }

  const existing = await prisma.machineType.findFirst({ where: { name } });
  if (existing) {
    let record = existing;
    if (description && existing.description !== description) {
      record = await prisma.machineType.update({
        where: { id: existing.id },
        data: { description },
      });
    }
    machineTypeCache.set(name, record);
    return record;
  }

  const created = await prisma.machineType.create({
    data: { name, description },
  });
  machineTypeCache.set(name, created);
  return created;
}

async function seedMachineTypes() {
  for (const machineType of MACHINE_TYPE_SEED_DATA) {
    await ensureMachineTypeByName(machineType.name, machineType.description);
  }
}

async function seedSkus() {
  for (const sku of SKU_SEED_DATA) {
    const record = await prisma.sKU.upsert({
      where: { code: sku.code },
      update: {
        name: sku.name,
        type: sku.type,
        category: sku.category,
      },
      create: {
        code: sku.code,
        name: sku.name,
        type: sku.type,
        category: sku.category,
      },
    });
    skuCache.set(record.code, record);
  }
}

async function getSkuByCode(code: string) {
  const cached = skuCache.get(code);
  if (cached) {
    return cached;
  }

  const sku = await prisma.sKU.findFirst({ where: { code } });
  if (!sku) {
    throw new Error(`SKU with code "${code}" is not seeded.`);
  }

  skuCache.set(code, sku);
  return sku;
}

const startOfDay = (date: Date) => {
  const copy = new Date(date);
  copy.setHours(0, 0, 0, 0);
  return copy;
};

const endOfDay = (date: Date) => {
  const copy = startOfDay(date);
  copy.setDate(copy.getDate() + 1);
  return copy;
};

const scheduleForDay = (daysFromToday: number, hour = 9) => {
  const date = new Date();
  date.setHours(hour, 0, 0, 0);
  date.setDate(date.getDate() + daysFromToday);
  return date;
};

async function hashUserPassword(password: string) {
  return hashPassword(password);
}

async function ensureCompany(name: string, timeZone?: string) {
  const existing = await prisma.company.findFirst({ where: { name } });
  if (existing) {
    if (timeZone && existing.timeZone !== timeZone) {
      return prisma.company.update({
        where: { id: existing.id },
        data: { timeZone },
      });
    }
    return existing;
  }

  return prisma.company.create({
    data: { name, timeZone },
  });
}

async function upsertUser({
  email,
  firstName,
  lastName,
  phone,
  role = UserRole.PICKER,
  password = DEFAULT_SEED_PASSWORD,
}: {
  email: string;
  firstName: string;
  lastName: string;
  phone?: string;
  role?: UserRole;
  password?: string;
}) {
  const hashedPassword = await hashUserPassword(password);
  const user = await prisma.user.upsert({
    where: { email },
    update: {
      firstName,
      lastName,
      phone,
      role,
      password: hashedPassword,
    },
    create: {
      email,
      firstName,
      lastName,
      phone,
      role,
      password: hashedPassword,
    },
  });

  return user;
}

async function ensureMembership(userId: string, companyId: string, role: UserRole) {
  const existing = await prisma.membership.findFirst({
    where: { userId, companyId },
  });

  if (existing) {
    if (existing.role !== role) {
      return prisma.membership.update({
        where: { id: existing.id },
        data: { role },
      });
    }
    return existing;
  }

  return prisma.membership.create({
    data: {
      userId,
      companyId,
      role,
    },
  });
}

async function ensureDefaultMembership(userId: string, membershipId: string) {
  const user = await prisma.user.findUniqueOrThrow({ where: { id: userId } });
  if (user.defaultMembershipId !== membershipId) {
    await prisma.user.update({
      where: { id: userId },
      data: { defaultMembershipId: membershipId },
    });
  }
}

async function ensureLocation(companyId: string, name: string, address?: string) {
  const existing = await prisma.location.findFirst({
    where: { companyId, name },
  });

  if (existing) {
    if (address && existing.address !== address) {
      return prisma.location.update({
        where: { id: existing.id },
        data: { address },
      });
    }
    return existing;
  }

  return prisma.location.create({
    data: {
      companyId,
      name,
      address,
    },
  });
}

async function ensureMachine({
  companyId,
  code,
  description,
  machineTypeId,
  locationId,
}: {
  companyId: string;
  code: string;
  description?: string;
  machineTypeId: string;
  locationId?: string;
}) {
  const existing = await prisma.machine.findFirst({
    where: { companyId, code },
  });

  if (existing) {
    if (
      existing.description !== description ||
      existing.locationId !== locationId ||
      existing.machineTypeId !== machineTypeId
    ) {
      return prisma.machine.update({
        where: { id: existing.id },
        data: {
          description,
          locationId,
          machineTypeId,
        },
      });
    }
    return existing;
  }

  return prisma.machine.create({
    data: {
      companyId,
      code,
      description,
      machineTypeId,
      locationId,
    },
  });
}

async function ensureCoil(machineId: string, code: string) {
  const existing = await prisma.coil.findFirst({
    where: { machineId, code },
  });

  if (existing) {
    return existing;
  }

  return prisma.coil.create({
    data: {
      machineId,
      code,
    },
  });
}

async function ensureCoilItem(coilId: string, skuId: string, par: number) {
  return prisma.coilItem.upsert({
    where: { coilId_skuId: { coilId, skuId } },
    update: { par },
    create: { coilId, skuId, par },
  });
}

async function ensureLocationWithEquipment(
  companyId: string,
  locationConfig: LocationSeedConfig,
): Promise<LocationSeedResult> {
  const location = await ensureLocation(companyId, locationConfig.name, locationConfig.address);
  const coilItems: CoilItemSeedInfo[] = [];

  for (const machineConfig of locationConfig.machines ?? []) {
    const machineTypeName = machineConfig.machineType ?? DEFAULT_MACHINE_TYPE_NAME;
    const machineTypeDesc = MACHINE_TYPE_SEED_DATA.find(
      (type) => type.name === machineTypeName,
    )?.description;
    const machineType = await ensureMachineTypeByName(machineTypeName, machineTypeDesc);

    const machine = await ensureMachine({
      companyId,
      code: machineConfig.code,
      description: machineConfig.description,
      machineTypeId: machineType.id,
      locationId: location.id,
    });

    for (const coilConfig of machineConfig.coils) {
      const coil = await ensureCoil(machine.id, coilConfig.code);
      const sku = await getSkuByCode(coilConfig.skuCode);
      const coilItem = await ensureCoilItem(coil.id, sku.id, coilConfig.par);
      coilItems.push({ id: coilItem.id, par: coilItem.par });
    }
  }

  return { location, coilItems };
}

async function syncRunLocations(runId: string, locationIds: string[]) {
  await prisma.runLocationOrder.deleteMany({ where: { runId } });
  if (!locationIds.length) {
    return;
  }

  await prisma.runLocationOrder.createMany({
    data: locationIds.map((locationId, index) => ({
      runId,
      locationId,
      position: index + 1,
    })),
  });
}

async function ensureRunWithLocations({
  companyId,
  pickerId,
  scheduledFor,
  locationIds,
}: {
  companyId: string;
  pickerId?: string;
  scheduledFor: Date;
  locationIds: string[];
}) {
  const existing = await prisma.run.findFirst({
    where: {
      companyId,
      scheduledFor: {
        gte: startOfDay(scheduledFor),
        lt: endOfDay(scheduledFor),
      },
    },
  });

  if (existing) {
    let run = existing;
    if (pickerId && existing.pickerId !== pickerId) {
      run = await prisma.run.update({
        where: { id: existing.id },
        data: { pickerId },
      });
    }
    await syncRunLocations(run.id, locationIds);
    return run;
  }

  const locationOrders =
    locationIds.length > 0
      ? {
          create: locationIds.map((locationId, index) => ({
            locationId,
            position: index + 1,
          })),
        }
      : undefined;

  return prisma.run.create({
    data: {
      companyId,
      pickerId,
      status: RunStatus.CREATED,
      scheduledFor,
      locationOrders,
    },
  });
}

async function ensurePickEntries(runId: string, coilItems: CoilItemSeedInfo[]) {
  await prisma.pickEntry.deleteMany({ where: { runId } });
  if (!coilItems.length) {
    return;
  }

  await prisma.pickEntry.createMany({
    data: coilItems.map((coilItem) => {
      const current = Math.max(coilItem.par - 3, 0);
      const need = Math.max(coilItem.par - current, 1);
      const total = current + need;
      return {
        runId,
        coilItemId: coilItem.id,
        count: need,
        current,
        par: coilItem.par,
        need,
        forecast: total,
        total,
        status: RunItemStatus.PENDING,
      };
    }),
  });
}

async function seedAppleTesting() {
  console.log('Creating Apple testing workspace...');
  const company = await ensureCompany(APP_STORE_COMPANY_NAME);

  const user = await upsertUser({
    email: APP_STORE_TEST_EMAIL,
    firstName: 'App Store',
    lastName: 'Testing Account',
    phone: 'TESTING-APPLE',
    role: UserRole.ADMIN,
    password: APP_STORE_TEST_PASSWORD,
  });

  const membership = await ensureMembership(user.id, company.id, UserRole.ADMIN);
  await ensureDefaultMembership(user.id, membership.id);

  const locationDetails: LocationSeedResult[] = [];
  for (const locationConfig of APPLE_LOCATION_CONFIG) {
    locationDetails.push(await ensureLocationWithEquipment(company.id, locationConfig));
  }

  if (!locationDetails.length) {
    throw new Error('Apple testing seed requires at least one configured location.');
  }

  const run = await ensureRunWithLocations({
    companyId: company.id,
    pickerId: user.id,
    scheduledFor: scheduleForDay(0),
    locationIds: [locationDetails[0].location.id],
  });
  await ensurePickEntries(run.id, locationDetails[0].coilItems);

  console.log('Apple testing company id:', company.id);
  console.log('Testing admin email:', APP_STORE_TEST_EMAIL);
  console.log('Testing admin password (plaintext):', APP_STORE_TEST_PASSWORD);
  console.log('Today run id:', run.id, 'scheduled for', run.scheduledFor?.toISOString());
}

async function seedCompanyData() {
  console.log('Creating general seed companies, owners, and runs...');
  const seeded = [];

  for (const config of COMPANY_SEED_CONFIG) {
    const company = await ensureCompany(config.name, config.timeZone);
    const owner = await upsertUser({
      email: config.owner.email,
      firstName: config.owner.firstName,
      lastName: config.owner.lastName,
      phone: config.owner.phone,
      role: UserRole.OWNER,
    });
    const membership = await ensureMembership(owner.id, company.id, UserRole.OWNER);
    await ensureDefaultMembership(owner.id, membership.id);

    const locationDetails: LocationSeedResult[] = [];
    for (const locationConfig of config.locations) {
      locationDetails.push(await ensureLocationWithEquipment(company.id, locationConfig));
    }

    if (!locationDetails.length) {
      throw new Error(`Company ${config.name} must have at least one location for seeding.`);
    }

    const todayLocation = locationDetails[0];
    const tomorrowLocation = locationDetails[1] ?? locationDetails[0];

    const todayRun = await ensureRunWithLocations({
      companyId: company.id,
      pickerId: owner.id,
      scheduledFor: scheduleForDay(0, 8),
      locationIds: [todayLocation.location.id],
    });
    await ensurePickEntries(todayRun.id, todayLocation.coilItems);

    const tomorrowRun = await ensureRunWithLocations({
      companyId: company.id,
      pickerId: owner.id,
      scheduledFor: scheduleForDay(1, 10),
      locationIds: [tomorrowLocation.location.id],
    });
    await ensurePickEntries(tomorrowRun.id, tomorrowLocation.coilItems);

    seeded.push({ company, owner, locations: locationDetails.map((detail) => detail.location) });
    console.log(`Seeded company "${company.name}" with owner ${owner.firstName} ${owner.lastName}`);
  }

  if (seeded.length >= 2) {
    // Add picker membership for the first owner in the second company
    const source = seeded[0];
    const target = seeded[1];
    await ensureMembership(source.owner.id, target.company.id, UserRole.PICKER);
    console.log(
      `${source.owner.firstName} ${source.owner.lastName} can now pick for ${target.company.name}`,
    );
  }

  return seeded;
}

async function seedExtraUsers() {
  console.log('Creating additional standalone users...');
  for (const user of EXTRA_USERS) {
    await upsertUser({
      ...user,
      role: UserRole.PICKER,
    });
  }
}

async function main() {
  await seedMachineTypes();
  await seedSkus();
  await seedAppleTesting();
  await seedCompanyData();
  await seedExtraUsers();
  console.log('Seed data completed.');
}

main()
  .catch((error) => {
    console.error('Failed to seed data:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
