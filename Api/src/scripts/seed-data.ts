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
const METRO_COMPANY_NAME = 'Metro Snacks Co.';
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

type SkuSeed = {
  code: string;
  name: string;
  type: string;
  category: string;
  weight?: number;
  isCheeseAndCrackers?: boolean;
  labelColour?: string;
};

const SKU_SEED_DATA: SkuSeed[] = [
  { code: 'SKU-PBAR-ALM', name: 'Protein Bar', type: 'Almond', category: 'confection', weight: 55 },
  { code: 'SKU-CHIPS-SEA', name: 'Chips', type: 'Sea Salt', category: 'confection', weight: 50 },
  { code: 'SKU-COFF-COLD', name: 'Cold Brew', type: 'Can', category: 'beverage', weight: 330 },
  { code: 'SKU-JUICE-CIT', name: 'Sparkling Juice', type: 'Bottle', category: 'beverage', weight: 375 },
  { code: 'SKU-ENERGY-MIX', name: 'Trail Mix', type: 'Original', category: 'confection', weight: 85 },
  { code: 'SKU-TEA-HERBAL', name: 'Herbal Tea', type: 'Unsweetened', category: 'beverage', weight: 500 },
  {
    code: 'SKU-CHEESE-CHED',
    name: 'Cheese & Crackers',
    type: 'Sharp Cheddar Pack',
    category: 'snack',
    weight: 48,
    isCheeseAndCrackers: true,
  },
  {
    code: 'SKU-CHEESE-GOUDA',
    name: 'Cheese & Crackers',
    type: 'Smoked Gouda Pack',
    category: 'snack',
    weight: 50,
    isCheeseAndCrackers: true,
  },
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

type MetroSalesRunConfig = {
  daysFromToday: number;
  hour: number;
  demandMultiplier: number;
  rotationOffset?: number;
  minLocations?: number;
  secondaryMinLocations?: number;
  secondaryRotationOffset?: number;
  secondaryDemandMultiplier?: number;
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
          { code: 'D1', skuCode: 'SKU-CHEESE-CHED', par: 10 },
          { code: 'D2', skuCode: 'SKU-CHEESE-GOUDA', par: 10 },
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
    name: METRO_COMPANY_NAME,
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
              { code: 'D1', skuCode: 'SKU-CHEESE-CHED', par: 12 },
              { code: 'D2', skuCode: 'SKU-CHEESE-GOUDA', par: 12 },
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
      {
        name: 'Harbor Innovation Hub',
        address: '42 River St, Mackay QLD 4740, Australia',
        machines: [
          {
            code: 'METRO-HARB-01',
            description: 'Harbor Snack Pilot',
            machineType: 'AMS Sensit 3',
            coils: [
              { code: 'A1', skuCode: 'SKU-PBAR-ALM', par: 15 },
              { code: 'A2', skuCode: 'SKU-ENERGY-MIX', par: 14 },
              { code: 'B1', skuCode: 'SKU-CHIPS-SEA', par: 13 },
            ],
          },
          {
            code: 'METRO-HARB-02',
            description: 'Harbor Beverage Cooler',
            machineType: 'DN BevMax 4',
            coils: [
              { code: 'C1', skuCode: 'SKU-COFF-COLD', par: 11 },
              { code: 'C2', skuCode: 'SKU-JUICE-CIT', par: 11 },
              { code: 'C3', skuCode: 'SKU-TEA-HERBAL', par: 12 },
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
              { code: 'D1', skuCode: 'SKU-CHEESE-CHED', par: 11 },
              { code: 'D2', skuCode: 'SKU-CHEESE-GOUDA', par: 11 },
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

// Gradual week-over-week growth with occasional softer weeks to mirror a real operation.
const METRO_WEEKS_TO_SEED = 30;

function clampMultiplier(value: number) {
  return Math.max(0.45, Math.min(1.08, Number(value.toFixed(2))));
}

// Gradual week-over-week growth with periodic soft dips to mimic real operations.
const METRO_SALES_HISTORY: MetroSalesRunConfig[] = buildMetroSalesHistory();

function buildMetroSalesHistory(): MetroSalesRunConfig[] {
  const weeks: MetroSalesRunConfig[] = [];
  const softDipWeeks = new Set([4, 9, 13, 18, 23, 27]); // Introduce occasional negative weeks.

  for (let index = 0; index < METRO_WEEKS_TO_SEED; index += 1) {
    const weeksAgo = index + 1;
    const seasonalPulse = ((index % 6) - 2) * 0.01; // Mild oscillation to avoid a flat line.
    const steadyLift = index * 0.018; // Long-term upward trend.
    const base = 0.58 + steadyLift + seasonalPulse;
    const dip = softDipWeeks.has(index) ? -0.06 : 0;
    const demandMultiplier = clampMultiplier(base + dip);
    const secondaryMultiplier = clampMultiplier(demandMultiplier * 0.78);
    const minLocations = Math.min(5, 2 + Math.floor(index / 6));
    const secondaryMinLocations = Math.max(2, minLocations - 1);

    weeks.push({
      daysFromToday: -7 * weeksAgo,
      hour: 8 + (index % 3),
      demandMultiplier,
      rotationOffset: index % 4,
      minLocations,
      secondaryMinLocations,
      secondaryRotationOffset: (index + 1) % 4,
      secondaryDemandMultiplier: secondaryMultiplier,
    });
  }

  return weeks;
}

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

const EXTRA_USERS: Array<{
  firstName: string;
  lastName: string;
  email: string;
  phone?: string | null;
  accountRole?: AccountRole | null;
  password?: string;
}> = [
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
const skuCacheKey = (code: string, companyId?: string | null) =>
  `${companyId ?? 'global'}:${code.toLowerCase()}`;

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
    const existing = await prisma.sKU.findFirst({
      where: { code: sku.code, companyId: null },
    });

    const data = {
      code: sku.code,
      name: sku.name,
      type: sku.type,
      category: sku.category,
      weight: toNullable(sku.weight),
      isCheeseAndCrackers: Boolean(sku.isCheeseAndCrackers),
      labelColour: toNullable(sku.labelColour),
    };

    const record = existing
      ? await prisma.sKU.update({
          where: { id: existing.id },
          data,
        })
      : await prisma.sKU.create({
          data,
        });

    skuCache.set(skuCacheKey(record.code, record.companyId), record);
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

async function getSkuForCompany(code: string, companyId: string) {
  const cacheKey = skuCacheKey(code, companyId);
  const cached = skuCache.get(cacheKey);
  if (cached) {
    return cached;
  }

  const existing = await prisma.sKU.findFirst({ where: { code, companyId } });
  if (existing) {
    skuCache.set(cacheKey, existing);
    return existing;
  }

  const template = await prisma.sKU.findFirst({ where: { code, companyId: null } });
  const seedDefinition = SKU_SEED_DATA.find((entry) => entry.code === code);

  const name = template?.name ?? seedDefinition?.name ?? code;
  const type = template?.type ?? seedDefinition?.type ?? 'General';
  const category = template?.category ?? seedDefinition?.category ?? null;
  const weight = template?.weight ?? seedDefinition?.weight ?? null;
  const isCheeseAndCrackers =
    template?.isCheeseAndCrackers ?? Boolean(seedDefinition?.isCheeseAndCrackers);
  const labelColour = template?.labelColour ?? seedDefinition?.labelColour ?? null;

  const created = await prisma.sKU.create({
    data: {
      code,
      name,
      type,
      category,
      weight: toNullable(weight),
      isCheeseAndCrackers,
      labelColour: toNullable(labelColour),
      company: {
        connect: { id: companyId },
      },
    },
  });

  skuCache.set(cacheKey, created);
  return created;
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
      const sku = await getSkuForCompany(coilConfig.skuCode, companyId);
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

async function resetCompanyRuns(companyId: string) {
  await prisma.run.deleteMany({
    where: { companyId },
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

function clampNeed(par: number, proposedNeed: number) {
  return Math.max(1, Math.min(proposedNeed, par));
}

function buildMetroPickSeeds(
  coilItems: CoilItemSeedInfo[],
  baseMultiplier: number,
  weekIndex: number,
): PickEntrySeed[] {
  return coilItems.map((coilItem, coilIndex) => {
    const weeklyPulse = ((weekIndex % 3) - 1) * 0.04;
    const machineDrift = ((coilItem.machineCode.length + coilIndex) % 5 - 2) * 0.03;
    const adjustedMultiplier = Math.max(
      0.35,
      Math.min(1.1, baseMultiplier + weeklyPulse + machineDrift),
    );
    const proposedNeed = Math.round(coilItem.par * adjustedMultiplier);
    const need = clampNeed(coilItem.par, proposedNeed);
    const current = Math.max(coilItem.par - need, 0);
    return makePickEntrySeed(coilItem, need, current);
  });
}

async function seedMetroSalesHistory(
  companyId: string,
  locationDetails: LocationSeedResult[],
) {
  if (!locationDetails.length) {
    return;
  }

  const totalLocations = locationDetails.length;
  const locationIds = locationDetails.map((detail) => detail.location.id);

  for (const [index, runConfig] of METRO_SALES_HISTORY.entries()) {
    const minLocations = Math.max(
      2,
      Math.min(totalLocations, runConfig.minLocations ?? MIN_RUN_LOCATIONS),
    );
    const rotationOffset = runConfig.rotationOffset ?? (index % totalLocations);

    const runLocations = selectRunLocations(locationDetails, rotationOffset, minLocations);
    const runLocationIds = runLocations.map((detail) => detail.location.id);
    const scheduledFor = scheduleForDay(runConfig.daysFromToday, runConfig.hour);

    const run = await ensureRunWithLocations({
      companyId,
      scheduledFor,
      locationIds: runLocationIds,
    });

    await prisma.run.update({
      where: { id: run.id },
      data: {
        status: RunStatus.READY,
        pickingStartedAt: new Date(scheduledFor.getTime() + 20 * 60 * 1000),
        pickingEndedAt: new Date(scheduledFor.getTime() + 2 * 60 * 60 * 1000),
      },
    });

    const pickSeeds = buildMetroPickSeeds(
      runLocations.flatMap((detail) => detail.coilItems),
      runConfig.demandMultiplier,
      index,
    );
    await seedPickEntriesWithConfig(run.id, pickSeeds);

    const secondaryMinLocations = Math.max(
      2,
      Math.min(
        totalLocations,
        runConfig.secondaryMinLocations ??
          Math.max(2, Math.min(totalLocations, minLocations + (index % 2 === 0 ? -1 : 1))),
      ),
    );
    const secondaryRotation =
      runConfig.secondaryRotationOffset ?? ((rotationOffset + 1) % Math.max(totalLocations, 1));
    const secondaryLocations = selectRunLocations(
      locationDetails,
      secondaryRotation,
      secondaryMinLocations,
    );
    const secondaryScheduledFor = scheduleForDay(runConfig.daysFromToday + 2, runConfig.hour + 1);
    const secondaryRun = await ensureRunWithLocations({
      companyId,
      scheduledFor: secondaryScheduledFor,
      locationIds: secondaryLocations.map((detail) => detail.location.id),
    });

    await prisma.run.update({
      where: { id: secondaryRun.id },
      data: {
        status: RunStatus.READY,
        pickingStartedAt: new Date(secondaryScheduledFor.getTime() + 15 * 60 * 1000),
        pickingEndedAt: new Date(secondaryScheduledFor.getTime() + 90 * 60 * 1000),
      },
    });

    const secondaryPickSeeds = buildMetroPickSeeds(
      secondaryLocations.flatMap((detail) => detail.coilItems),
      runConfig.secondaryDemandMultiplier ?? Math.max(0.4, runConfig.demandMultiplier * 0.7),
      index + 1,
    );
    await seedPickEntriesWithConfig(secondaryRun.id, secondaryPickSeeds);
  }
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

    if (config.name === METRO_COMPANY_NAME) {
      await resetCompanyRuns(company.id);
    }

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

    if (config.name === METRO_COMPANY_NAME) {
      await seedMetroSalesHistory(company.id, locationDetails);
    }

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
