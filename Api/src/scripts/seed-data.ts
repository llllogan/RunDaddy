/*
Seed Overview

Companies
+-------------------------------+---------------+--------------------------------------+---------------------+
| Company                       | Tier          | Owner Email                          | Time Zone           |
+-------------------------------+---------------+--------------------------------------+------------------------+
| Apple                         | Enterprise 10 | appstore-testing@apple.com           | Australia/Brisbane    |
| Metro Snacks Co.              | Business      | taylor.kent+seed@rundaddy.test       | Australia/Brisbane    |
| River City Logistics          | Business      | jordan.blake+seed@rundaddy.test      | Australia/Brisbane    |
| Pulse Logistics Collective    | Individual    | morgan.hart+seed@rundaddy.test       | Australia/Brisbane    |
+-------------------------------+---------------+--------------------------------------+------------------------+

Users
+----------------------------+-----------------------------------+-----------------------+-----------------------------------------------------------+
| Name                       | Email                             | Password              | Memberships                                               |
+----------------------------+-----------------------------------+-----------------------+-----------------------------------------------------------+
| App Store Testing Account  | appstore-testing@apple.com        | AppleTestingOnly!123* | Apple (OWNER)                                             |
| Taylor Kent                | taylor.kent+seed@rundaddy.test    | SeedDataPass!123*     | Metro Snacks Co. (OWNER); River City Logistics (PICKER)   |
| Jordan Blake               | jordan.blake+seed@rundaddy.test   | SeedDataPass!123*     | River City Logistics (OWNER)                              |
| Morgan Hart                | morgan.hart+seed@rundaddy.test    | SeedDataPass!123*     | Pulse Logistics Collective (OWNER)                        |
| Casey Nguyen               | casey.nguyen+seed@rundaddy.test   | SeedDataPass!123*     | None                                                      |
| Skyler Lopez               | skyler.lopez+seed@rundaddy.test   | SeedDataPass!123*     | None                                                      |
| Lighthouse Admin           | lighthouse@admin.com              | SeedDataPass!123*     | None (account role LIGHTHOUSE)                            |
+----------------------------+-----------------------------------+-----------------------+-----------------------------------------------------------+
* Passwords overrideable via APP_STORE_TEST_PASSWORD or SEED_USER_PASSWORD.
*/

import { AccountRole, RunStatus, UserRole } from '@prisma/client';
import type { Location, MachineType, SKU } from '@prisma/client';
import { prisma } from '../lib/prisma.js';
import { hashPassword } from '../lib/password.js';
import { TIER_IDS, TIER_SEED_DATA } from '../config/tiers.js';

const BRISBANE_TIME_ZONE = 'Australia/Brisbane';
const BRISBANE_OFFSET_MINUTES = 10 * 60; // Queensland stays on UTC+10 year-round (no DST).
const APP_STORE_COMPANY_NAME = 'Apple';
const APP_STORE_TEST_EMAIL = process.env.APP_STORE_TEST_EMAIL ?? 'appstore-testing@apple.com';
const APP_STORE_TEST_PASSWORD = process.env.APP_STORE_TEST_PASSWORD ?? 'AppleTestingOnly!123';
const APP_STORE_TIME_ZONE = BRISBANE_TIME_ZONE;
const APP_STORE_TIER_ID = TIER_IDS.ENTERPRISE_10;
const DEFAULT_SEED_PASSWORD = process.env.SEED_USER_PASSWORD ?? 'SeedDataPass!123';
const MIN_RUN_LOCATIONS = 4;

const MACHINE_TYPE_SEED_DATA = [
  { name: 'AMS Sensit 3', description: 'Snack' },
  { name: 'DN BevMax 4', description: 'Food/Bev' },
  { name: 'Vendo Vue GF', description: 'GF Bev' },
  { name: 'Crane GF Fresh', description: 'GF Food' },
  { name: 'Mars Merchant', description: 'Confectionary' },
  { name: 'USI Combo Plus', description: 'Snakc/Food' },
];

const DEFAULT_MACHINE_TYPE_NAME =
  MACHINE_TYPE_SEED_DATA[0]?.name ??
  (() => {
    throw new Error('At least one machine type seed entry is required.');
  })();

const SKU_SEED_DATA = [
  { code: 'SKU-PBAR-ALM', name: 'Protein Bar', type: 'Almond', category: 'confection' },
  { code: 'SKU-CHIPS-SEA', name: 'Chips', type: 'Sea Salt', category: 'confection' },
  { code: 'SKU-COFF-COLD', name: 'Cold Brew', type: 'Can', category: 'beverage' },
  { code: 'SKU-JUICE-CIT', name: 'Sparkling Juice', type: 'Bottle', category: 'beverage' },
  { code: 'SKU-ENERGY-MIX', name: 'Trail Mix', type: 'Original', category: 'confection' },
  { code: 'SKU-TEA-HERBAL', name: 'Herbal Tea', type: 'Unsweetened', category: 'beverage' },
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
  tierId: string;
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
    address: '43 Esplanade, Golden Beach QLD 4551, Australia', // Sunshine Coast south end
    machines: [
      {
        code: 'APPLE-SNACK-1',
        description: 'Testing snack machine',
        machineType: 'AMS Sensit 3',
        coils: [
          { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 12 },
          { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 16 },
          { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 14 },
        ],
      },
      {
        code: 'APPLE-BEV-1',
        description: 'Chilled beverage validation unit',
        machineType: 'DN BevMax 4',
        coils: [
          { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 12 },
          { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 12 },
          { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 10 },
        ],
      },
    ],
  },
  {
    name: 'Apple Developer Center West',
    address: '8 Innovation Pkwy, Birtinya QLD 4575, Australia',
    machines: [
      {
        code: 'APPLE-DEV-SNACK',
        description: 'Developer snack staging',
        machineType: 'AMS Sensit 3',
        coils: [
          { code: 'A1', skuCode: 'SKU-ENERGY-MIX', par: 18 },
          { code: 'A2', skuCode: 'SKU-PBAR-ALM', par: 15 },
          { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 16 },
        ],
      },
      {
        code: 'APPLE-DEV-BEV',
        description: 'Developer beverage staging',
        machineType: 'DN BevMax 4',
        coils: [
          { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 10 },
          { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 14 },
          { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 12 },
        ],
      },
    ],
  },
  {
    name: 'Apple Infinite Loop Labs',
    address: '123 Parklands Blvd, Little Mountain QLD 4551, Australia',
    machines: [
      {
        code: 'APPLE-INF-SNACK',
        description: 'Legacy campus snack tower',
        machineType: 'AMS Sensit 3',
        coils: [
          { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 17 },
          { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 17 },
          { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 15 },
        ],
      },
      {
        code: 'APPLE-INF-BEV',
        description: 'Legacy campus beverage cooler',
        machineType: 'DN BevMax 4',
        coils: [
          { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 11 },
          { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 11 },
          { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 13 },
        ],
      },
    ],
  },
  {
    name: 'Apple Sunnyvale Logistics Hub',
    address: '1 Metier Linkway, Birtinya QLD 4575, Australia',
    machines: [
      {
        code: 'APPLE-SUN-SNACK',
        description: 'Logistics snack machine',
        machineType: 'AMS Sensit 3',
        coils: [
          { code: 'A1', skuCode: 'SKU-ENERGY-MIX', par: 20 },
          { code: 'A2', skuCode: 'SKU-PBAR-ALM', par: 18 },
          { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 19 },
        ],
      },
      {
        code: 'APPLE-SUN-BEV',
        description: 'Logistics beverage machine',
        machineType: 'DN BevMax 4',
        coils: [
          { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 13 },
          { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 15 },
          { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 14 },
        ],
      },
    ],
  },
];

const COMPANY_SEED_CONFIG: CompanySeedConfig[] = [
  {
    name: 'Metro Snacks Co.',
    timeZone: BRISBANE_TIME_ZONE,
    tierId: TIER_IDS.BUSINESS,
    owner: {
      firstName: 'Taylor',
      lastName: 'Kent',
      email: 'taylor.kent+seed@rundaddy.test',
      phone: '555-0101',
    },
    locations: [
      {
        name: 'Metro Warehouse',
        address: '112 Redland Bay Rd, Capalaba QLD 4157, Australia', // Mainland hub near Redland Bay
        machines: [
          {
            code: 'METRO-WH-01',
            description: 'Warehouse Snack Tower',
            machineType: 'AMS Sensit 3',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 18 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 15 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 20 },
            ],
          },
          {
            code: 'METRO-WH-02',
            description: 'Warehouse Beverage Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 14 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 12 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 13 },
            ],
          },
          {
            code: 'METRO-WH-03',
            description: 'Warehouse Combo Unit',
            machineType: 'USI Combo Plus',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 14 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 14 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 16 },
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 10 },
            ],
          },
          {
            code: 'METRO-WH-04',
            description: 'Warehouse Overflow Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 12 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 12 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 12 },
            ],
          },
        ],
      },
      {
        name: 'Downtown Drop Off',
        address: '1/11-19 Beerburrum St, Dicky Beach QLD 4551, Australia',
        machines: [
          {
            code: 'METRO-DT-01',
            description: 'Downtown Beverage Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 12 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 10 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 14 },
            ],
          },
          {
            code: 'METRO-DT-02',
            description: 'Downtown Snack Tower',
            machineType: 'AMS Sensit 3',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 16 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 15 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 17 },
            ],
          },
        ],
      },
      {
        name: 'Mission Corporate Campus',
        address: '99 Gympie Rd, Strathpine QLD 4500, Australia',
        machines: [
          {
            code: 'METRO-MIS-01',
            description: 'Mission Campus Snack Tower',
            machineType: 'AMS Sensit 3',
            coils: [
              { code: 'A1', skuCode: 'SKU-ENERGY-MIX', par: 17 },
              { code: 'A2', skuCode: 'SKU-PBAR-ALM', par: 16 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 18 },
            ],
          },
          {
            code: 'METRO-MIS-02',
            description: 'Mission Campus Beverage Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 11 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 13 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 12 },
            ],
          },
        ],
      },
      {
        name: 'Bayview Distribution Hub',
        address: '15 Anzac Ave, Redcliffe QLD 4020, Australia',
        machines: [
          {
            code: 'METRO-BAY-01',
            description: 'Bayview Snack Tower',
            machineType: 'AMS Sensit 3',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 19 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 18 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 19 },
            ],
          },
          {
            code: 'METRO-BAY-02',
            description: 'Bayview Beverage Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 15 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 14 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 15 },
            ],
          },
        ],
      },
    ],
  },
  {
    name: 'River City Logistics',
    timeZone: BRISBANE_TIME_ZONE,
    tierId: TIER_IDS.BUSINESS,
    owner: {
      firstName: 'Jordan',
      lastName: 'Blake',
      email: 'jordan.blake+seed@rundaddy.test',
      phone: '555-0202',
    },
    locations: [
      {
        name: 'River City HQ',
        address: '10/2 Capital Pl, Birtinya QLD 4575, Australia',
        machines: [
          {
            code: 'RIVER-HQ-01',
            description: 'HQ Snack Tower',
            machineType: 'AMS Sensit 3',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 16 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 14 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 18 },
            ],
          },
          {
            code: 'RIVER-HQ-02',
            description: 'HQ Beverage Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 11 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 12 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 12 },
            ],
          },
        ],
      },
      {
        name: 'Aurora Route',
        address: '1852 Logan Rd, Upper Mount Gravatt QLD 4122, Australia', // South towards Logan
        machines: [
          {
            code: 'RIVER-AU-01',
            description: 'Aurora Beverage Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 10 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 12 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 11 },
            ],
          },
          {
            code: 'RIVER-AU-02',
            description: 'Aurora Snack Tower',
            machineType: 'AMS Sensit 3',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 15 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 13 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 16 },
            ],
          },
        ],
      },
      {
        name: 'Stapleton Tech Park',
        address: '52 Wembley Rd, Logan Central QLD 4114, Australia',
        machines: [
          {
            code: 'RIVER-ST-01',
            description: 'Stapleton Snack Tower',
            machineType: 'AMS Sensit 3',
            coils: [
              { code: 'A1', skuCode: 'SKU-ENERGY-MIX', par: 17 },
              { code: 'A2', skuCode: 'SKU-PBAR-ALM', par: 15 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 17 },
            ],
          },
          {
            code: 'RIVER-ST-02',
            description: 'Stapleton Beverage Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 13 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 14 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 13 },
            ],
          },
        ],
      },
      {
        name: 'Boulder Medical Campus',
        address: '9 Macrossan St, Brisbane City QLD 4000, Australia',
        machines: [
          {
            code: 'RIVER-BO-01',
            description: 'Boulder Snack Tower',
            machineType: 'AMS Sensit 3',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 18 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 17 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 18 },
            ],
          },
          {
            code: 'RIVER-BO-02',
            description: 'Boulder Beverage Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 12 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 13 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 15 },
            ],
          },
        ],
      },
    ],
  },
];

const TREND_SCENARIO_COMPANY = {
  name: 'Pulse Logistics Collective',
  timeZone: BRISBANE_TIME_ZONE,
  tierId: TIER_IDS.INDIVIDUAL,
  owner: {
    firstName: 'Morgan',
    lastName: 'Hart',
    email: 'morgan.hart+seed@rundaddy.test',
    phone: '555-0606',
  },
  locations: [
    {
      name: 'Pulse Uptown Lab',
      address: '16 Austin St, Newstead QLD 4006, Australia',
      machines: [
        {
          code: 'PULSE-UP-01',
          description: 'Uptown snack pilot',
          machineType: 'AMS Sensit 3',
          coils: [
            { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 16 },
            { code: 'A2', skuCode: 'SKU-CHIPS-SEA', par: 15 },
          ],
        },
      ],
    },
    {
      name: 'Pulse Riverfront Clinic',
      address: '12 Cordelia St, South Brisbane QLD 4101, Australia',
      machines: [
        {
          code: 'PULSE-RF-01',
          description: 'Riverfront beverage pilot',
          machineType: 'DN BevMax 4',
          coils: [
            { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 12 },
            { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 11 },
          ],
        },
      ],
    },
  ],
};

type TrendPickNeed = {
  machineCode: string;
  skuCode: string;
  need: number;
};

const TREND_SCENARIO_PICK_CONFIG: Record<'lastWeek' | 'thisWeek', TrendPickNeed[]> = {
  lastWeek: [
    { machineCode: 'PULSE-UP-01', skuCode: 'SKU-PBAR-ALM', need: 5 },
    { machineCode: 'PULSE-UP-01', skuCode: 'SKU-CHIPS-SEA', need: 3 },
    { machineCode: 'PULSE-RF-01', skuCode: 'SKU-COFF-COLD', need: 4 },
    { machineCode: 'PULSE-RF-01', skuCode: 'SKU-JUICE-CIT', need: 4 },
  ],
  thisWeek: [
    { machineCode: 'PULSE-UP-01', skuCode: 'SKU-PBAR-ALM', need: 9 },
    { machineCode: 'PULSE-UP-01', skuCode: 'SKU-CHIPS-SEA', need: 2 },
    { machineCode: 'PULSE-RF-01', skuCode: 'SKU-COFF-COLD', need: 3 },
    { machineCode: 'PULSE-RF-01', skuCode: 'SKU-JUICE-CIT', need: 2 },
  ],
};

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
  {
    firstName: 'Lighthouse',
    lastName: 'Admin',
    email: 'lighthouse@admin.com',
    phone: '555-0505',
    accountRole: AccountRole.LIGHTHOUSE,
  },
];

const machineTypeCache = new Map<string, MachineType>();
const skuCache = new Map<string, SKU>();

type CoilItemSeedInfo = {
  id: string;
  par: number;
  machineCode: string;
  skuCode: string;
};

const toNullable = <T>(value: T | null | undefined): T | null => (value ?? null);

async function ensureMachineTypeByName(name: string, description?: string) {
  const cached = machineTypeCache.get(name);
  if (cached) {
    if (description && cached.description !== description) {
      const updated = await prisma.machineType.update({
        where: { id: cached.id },
        data: { description: toNullable(description) },
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
        data: { description: toNullable(description) },
      });
    }
    machineTypeCache.set(name, record);
    return record;
  }

  const created = await prisma.machineType.create({
    data: { name, description: toNullable(description) },
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

async function seedTierConsts() {
  console.log('Seeding tier constraints...');
  for (const tier of TIER_SEED_DATA) {
    await prisma.tierConsts.upsert({
      where: { id: tier.id },
      update: {
        name: tier.name,
        maxOwners: tier.maxOwners,
        maxAdmins: tier.maxAdmins,
        maxPickers: tier.maxPickers,
        canBreakDownRun: tier.canBreakDownRun,
      },
      create: {
        id: tier.id,
        name: tier.name,
        maxOwners: tier.maxOwners,
        maxAdmins: tier.maxAdmins,
        maxPickers: tier.maxPickers,
        canBreakDownRun: tier.canBreakDownRun,
      },
    });
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

const scheduleForDay = (daysFromToday: number, hour = 9) => {
  const offsetMs = BRISBANE_OFFSET_MINUTES * 60 * 1000;
  const brisbaneNow = new Date(Date.now() + offsetMs);

  const targetLocal = Date.UTC(
    brisbaneNow.getUTCFullYear(),
    brisbaneNow.getUTCMonth(),
    brisbaneNow.getUTCDate() + daysFromToday,
    hour,
    0,
    0,
    0,
  );

  // Convert the Brisbane local wall time back to the actual UTC instant.
  return new Date(targetLocal - offsetMs);
};

async function hashUserPassword(password: string) {
  return hashPassword(password);
}

async function ensureCompany(name: string, tierId: string, timeZone?: string | null) {
  const existing = await prisma.company.findFirst({ where: { name } });
  if (existing) {
    const data: { timeZone?: string | null; tierId?: string } = {};

    if (timeZone !== undefined && existing.timeZone !== timeZone) {
      data.timeZone = toNullable(timeZone);
    }

    if (existing.tierId !== tierId) {
      data.tierId = tierId;
    }

    if (Object.keys(data).length > 0) {
      return prisma.company.update({
        where: { id: existing.id },
        data,
      });
    }

    return existing;
  }

  return prisma.company.create({
    data: { name, tierId, timeZone: toNullable(timeZone) },
  });
}

async function upsertUser({
  email,
  firstName,
  lastName,
  phone,
  accountRole = null,
  password = DEFAULT_SEED_PASSWORD,
}: {
  email: string;
  firstName: string;
  lastName: string;
  phone?: string | null;
  accountRole?: AccountRole | null;
  password?: string;
}) {
  const hashedPassword = await hashUserPassword(password);
  const user = await prisma.user.upsert({
    where: { email },
    update: {
      firstName,
      lastName,
      phone: toNullable(phone),
      password: hashedPassword,
      role: accountRole ?? null,
    },
    create: {
      email,
      firstName,
      lastName,
      phone: toNullable(phone),
      password: hashedPassword,
      role: accountRole ?? null,
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

async function ensureLocation(companyId: string, name: string, address?: string | null) {
  const existing = await prisma.location.findFirst({
    where: { companyId, name },
  });

  if (existing) {
    if (address && existing.address !== address) {
      return prisma.location.update({
        where: { id: existing.id },
        data: { address: toNullable(address) },
      });
    }
    return existing;
  }

  return prisma.location.create({
    data: {
      companyId,
      name,
      address: toNullable(address),
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
  description?: string | null;
  machineTypeId: string;
  locationId?: string | null;
}) {
  const existing = await prisma.machine.findFirst({
    where: { companyId, code },
  });

  if (existing) {
    const descriptionChanged = description !== undefined && existing.description !== description;
    const locationChanged = locationId !== undefined && existing.locationId !== locationId;
    const machineTypeChanged = existing.machineTypeId !== machineTypeId;

    if (descriptionChanged || locationChanged || machineTypeChanged) {
      return prisma.machine.update({
        where: { id: existing.id },
        data: {
          ...(descriptionChanged ? { description: toNullable(description) } : {}),
          ...(locationChanged ? { locationId: toNullable(locationId) } : {}),
          ...(machineTypeChanged ? { machineTypeId } : {}),
        },
      });
    }
    return existing;
  }

  return prisma.machine.create({
    data: {
      companyId,
      code,
      description: toNullable(description),
      machineTypeId,
      locationId: toNullable(locationId),
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
      description: machineConfig.description ?? null,
      machineTypeId: machineType.id,
      locationId: location.id,
    });

    for (const coilConfig of machineConfig.coils) {
      const coil = await ensureCoil(machine.id, coilConfig.code);
      const sku = await getSkuByCode(coilConfig.skuCode);
      const coilItem = await ensureCoilItem(coil.id, sku.id, coilConfig.par);
      coilItems.push({
        id: coilItem.id,
        par: coilItem.par,
        machineCode: machineConfig.code,
        skuCode: coilConfig.skuCode,
      });
    }
  }

  return { location, coilItems };
}

function selectRunLocations(
  locationDetails: LocationSeedResult[],
  startIndex = 0,
  minimum = MIN_RUN_LOCATIONS,
): LocationSeedResult[] {
  if (!locationDetails.length) {
    return [];
  }

  const rotated = locationDetails.slice(startIndex).concat(locationDetails.slice(0, startIndex));
  if (rotated.length < minimum) {
    return rotated;
  }

  return rotated.slice(0, minimum);
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
  scheduledFor,
  locationIds,
}: {
  companyId: string;
  scheduledFor: Date;
  locationIds: string[];
}) {
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
      status: RunStatus.CREATED,
      scheduledFor,
      ...(locationOrders ? { locationOrders } : {}),
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
        isPicked: false,
      };
    }),
  });
}

type PickEntrySeed = {
  coilItemId: string;
  par: number;
  current: number;
  need: number;
};

const buildCoilItemLookup = (locationDetails: LocationSeedResult[]) => {
  const map = new Map<string, CoilItemSeedInfo>();
  for (const detail of locationDetails) {
    for (const coilItem of detail.coilItems) {
      map.set(`${coilItem.machineCode}:${coilItem.skuCode}`, coilItem);
    }
  }
  return map;
};

const makePickEntrySeed = (
  coilItem: CoilItemSeedInfo,
  need: number,
  current?: number,
): PickEntrySeed => {
  const resolvedCurrent = current ?? Math.max(coilItem.par - need, 0);
  return {
    coilItemId: coilItem.id,
    par: coilItem.par,
    current: resolvedCurrent,
    need,
  };
};

async function seedPickEntriesWithConfig(runId: string, entries: PickEntrySeed[]) {
  await prisma.pickEntry.deleteMany({ where: { runId } });
  if (!entries.length) {
    return;
  }

  await prisma.pickEntry.createMany({
    data: entries.map((entry) => {
      const total = entry.current + entry.need;
      return {
        runId,
        coilItemId: entry.coilItemId,
        par: entry.par,
        current: entry.current,
        need: entry.need,
        count: entry.need,
        forecast: total,
        total,
        isPicked: false,
      };
    }),
  });
}

async function seedAppleTesting() {
  console.log('Creating Apple testing workspace...');
  const company = await ensureCompany(APP_STORE_COMPANY_NAME, APP_STORE_TIER_ID, APP_STORE_TIME_ZONE);

  const user = await upsertUser({
    email: APP_STORE_TEST_EMAIL,
    firstName: 'App Store',
    lastName: 'Testing Account',
    phone: 'TESTING-APPLE',
    password: APP_STORE_TEST_PASSWORD,
  });

  const membership = await ensureMembership(user.id, company.id, UserRole.OWNER);
  await ensureDefaultMembership(user.id, membership.id);

  const locationDetails: LocationSeedResult[] = [];
  for (const locationConfig of APPLE_LOCATION_CONFIG) {
    locationDetails.push(await ensureLocationWithEquipment(company.id, locationConfig));
  }

  if (locationDetails.length < MIN_RUN_LOCATIONS) {
    throw new Error('Apple testing seed requires at least four configured locations.');
  }

  const runLocations = selectRunLocations(locationDetails);
  const runLocationIds = runLocations.map((detail) => detail.location.id);
  const runCoilItems = runLocations.flatMap((detail) => detail.coilItems);

  const run = await ensureRunWithLocations({
    companyId: company.id,
    scheduledFor: scheduleForDay(0),
    locationIds: runLocationIds,
  });
  await ensurePickEntries(run.id, runCoilItems);

  console.log('Apple testing company id:', company.id);
  console.log('Testing admin email:', APP_STORE_TEST_EMAIL);
  console.log('Testing admin password (plaintext):', APP_STORE_TEST_PASSWORD);
  console.log('Today run id:', run.id, 'scheduled for', run.scheduledFor?.toISOString());
}

async function seedCompanyData() {
  console.log('Creating general seed companies, owners, and runs...');
  const seeded = [];

  for (const config of COMPANY_SEED_CONFIG) {
    const company = await ensureCompany(config.name, config.tierId, config.timeZone);
    const owner = await upsertUser({
      email: config.owner.email,
      firstName: config.owner.firstName,
      lastName: config.owner.lastName,
      phone: config.owner.phone ?? null,
    });
    const membership = await ensureMembership(owner.id, company.id, UserRole.OWNER);
    await ensureDefaultMembership(owner.id, membership.id);

    const locationDetails: LocationSeedResult[] = [];
    for (const locationConfig of config.locations) {
      locationDetails.push(await ensureLocationWithEquipment(company.id, locationConfig));
    }

    if (locationDetails.length < MIN_RUN_LOCATIONS) {
      throw new Error(
        `Company ${config.name} must have at least ${MIN_RUN_LOCATIONS} locations for seeding.`,
      );
    }

    const todayLocations = selectRunLocations(locationDetails, 0);
    const tomorrowLocations = selectRunLocations(locationDetails, 2);

    const todayRun = await ensureRunWithLocations({
      companyId: company.id,
      scheduledFor: scheduleForDay(0, 8),
      locationIds: todayLocations.map((detail) => detail.location.id),
    });
    await ensurePickEntries(todayRun.id, todayLocations.flatMap((detail) => detail.coilItems));

    const tomorrowRun = await ensureRunWithLocations({
      companyId: company.id,
      scheduledFor: scheduleForDay(1, 10),
      locationIds: tomorrowLocations.map((detail) => detail.location.id),
    });
    await ensurePickEntries(
      tomorrowRun.id,
      tomorrowLocations.flatMap((detail) => detail.coilItems),
    );

    seeded.push({ company, owner, locations: locationDetails.map((detail) => detail.location) });
    console.log(`Seeded company "${company.name}" with owner ${owner.firstName} ${owner.lastName}`);
  }

  if (seeded.length >= 2) {
    // Add picker membership for the first owner in the second company
    const source = seeded[0];
    const target = seeded[1];
    if (source && target) {
      await ensureMembership(source.owner.id, target.company.id, UserRole.PICKER);
      console.log(
        `${source.owner.firstName} ${source.owner.lastName} can now pick for ${target.company.name}`,
      );
    }
  }

  return seeded;
}

function toPickEntrySeeds(
  lookup: Map<string, CoilItemSeedInfo>,
  configs: TrendPickNeed[],
): PickEntrySeed[] {
  return configs.map((config) => {
    const key = `${config.machineCode}:${config.skuCode}`;
    const coilItem = lookup.get(key);
    if (!coilItem) {
      throw new Error(`Missing coil item for ${config.machineCode} ${config.skuCode}`);
    }
    return makePickEntrySeed(coilItem, config.need);
  });
}

async function seedTrendScenarioCompany() {
  console.log('Creating trend comparison company...');
  const company = await ensureCompany(
    TREND_SCENARIO_COMPANY.name,
    TREND_SCENARIO_COMPANY.tierId,
    TREND_SCENARIO_COMPANY.timeZone,
  );
  const owner = await upsertUser({
    email: TREND_SCENARIO_COMPANY.owner.email,
    firstName: TREND_SCENARIO_COMPANY.owner.firstName,
    lastName: TREND_SCENARIO_COMPANY.owner.lastName,
    phone: TREND_SCENARIO_COMPANY.owner.phone ?? null,
  });
  const membership = await ensureMembership(owner.id, company.id, UserRole.OWNER);
  await ensureDefaultMembership(owner.id, membership.id);

  const locationDetails: LocationSeedResult[] = [];
  for (const locationConfig of TREND_SCENARIO_COMPANY.locations) {
    locationDetails.push(await ensureLocationWithEquipment(company.id, locationConfig));
  }

  const locationIds = locationDetails.map((detail) => detail.location.id);
  const coilLookup = buildCoilItemLookup(locationDetails);

  const lastWeekRun = await ensureRunWithLocations({
    companyId: company.id,
    scheduledFor: scheduleForDay(-7, 9),
    locationIds,
  });
  await seedPickEntriesWithConfig(
    lastWeekRun.id,
    toPickEntrySeeds(coilLookup, TREND_SCENARIO_PICK_CONFIG.lastWeek),
  );

  const thisWeekRun = await ensureRunWithLocations({
    companyId: company.id,
    scheduledFor: scheduleForDay(0, 10),
    locationIds,
  });
  await seedPickEntriesWithConfig(
    thisWeekRun.id,
    toPickEntrySeeds(coilLookup, TREND_SCENARIO_PICK_CONFIG.thisWeek),
  );

  console.log(
    `Trend company "${company.name}" ready with user ${owner.email} and runs ${lastWeekRun.id} / ${thisWeekRun.id}`,
  );
}

async function seedExtraUsers() {
  console.log('Creating additional standalone users...');
  for (const user of EXTRA_USERS) {
    await upsertUser({
      ...user,
      accountRole: user.accountRole ?? null,
    });
  }
}

async function main() {
  await seedMachineTypes();
  await seedSkus();
  await seedTierConsts();
  await seedAppleTesting();
  await seedCompanyData();
  await seedTrendScenarioCompany();
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
