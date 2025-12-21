import { TIER_IDS } from './tiers.js';

export const STRIPE_PRICE_IDS: Record<string, string> = {
  [TIER_IDS.INDIVIDUAL]: process.env.STRIPE_PRICE_INDIVIDUAL ?? '',
  [TIER_IDS.BUSINESS]: process.env.STRIPE_PRICE_BUSINESS ?? '',
  [TIER_IDS.ENTERPRISE_10]: process.env.STRIPE_PRICE_ENTERPRISE_10 ?? '',
};

export const STRIPE_SUCCESS_URL =
  process.env.STRIPE_SUCCESS_URL ?? 'http://localhost:4200/dashboard';
export const STRIPE_CANCEL_URL =
  process.env.STRIPE_CANCEL_URL ?? 'http://localhost:4200/signup';
