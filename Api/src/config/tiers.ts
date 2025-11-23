export const TIER_IDS = {
  INDIVIDUAL: 'tier-individual',
  BUSINESS: 'tier-business',
  ENTERPRISE_10: 'tier-enterprise-10',
} as const;

export type TierSeedConfig = {
  id: string;
  name: string;
  maxOwners: number;
  maxAdmins: number;
  maxPickers: number;
  canBreakDownRun: boolean;
};

export const TIER_SEED_DATA: TierSeedConfig[] = [
  {
    id: TIER_IDS.INDIVIDUAL,
    name: 'Individual',
    maxOwners: 1,
    maxAdmins: 0,
    maxPickers: 0,
    canBreakDownRun: false,
  },
  {
    id: TIER_IDS.BUSINESS,
    name: 'Business',
    maxOwners: 1,
    maxAdmins: 1,
    maxPickers: 2,
    canBreakDownRun: true,
  },
  {
    id: TIER_IDS.ENTERPRISE_10,
    name: 'Enterprise 10',
    maxOwners: 1,
    maxAdmins: 2,
    maxPickers: 10,
    canBreakDownRun: true,
  },
];

export const DEFAULT_COMPANY_TIER_ID = TIER_IDS.BUSINESS;
