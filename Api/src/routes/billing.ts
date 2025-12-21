import { Router, type Request, type Response } from 'express';
import type Stripe from 'stripe';
import { prisma } from '../lib/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { setLogConfig } from '../middleware/logging.js';
import { getStripe } from '../lib/stripe.js';
import { STRIPE_CANCEL_URL, STRIPE_PRICE_IDS, STRIPE_SUCCESS_URL } from '../config/stripe.js';
import { TIER_IDS } from '../config/tiers.js';
import { BillingStatus } from '../types/enums.js';
import { isCompanyManager } from './helpers/authorization.js';

const router = Router();

const getStripePriceId = (tierId: string): string | null => {
  const priceId = STRIPE_PRICE_IDS[tierId];
  return priceId && priceId.trim().length > 0 ? priceId : null;
};

const mapStripeStatus = (status: Stripe.Subscription.Status): BillingStatus => {
  switch (status) {
    case 'active':
      return BillingStatus.ACTIVE;
    case 'trialing':
      return BillingStatus.TRIALING;
    case 'past_due':
      return BillingStatus.PAST_DUE;
    case 'unpaid':
      return BillingStatus.UNPAID;
    case 'canceled':
      return BillingStatus.CANCELED;
    case 'incomplete':
    case 'incomplete_expired':
      return BillingStatus.INCOMPLETE;
    case 'paused':
      return BillingStatus.PAST_DUE;
    default:
      return BillingStatus.CANCELED;
  }
};

const resolveCompanyForStripe = async (params: {
  subscriptionId?: string | null;
  customerId?: string | null;
}) => {
  const whereOr: Array<{ stripeSubscriptionId?: string; stripeCustomerId?: string }> = [];

  if (params.subscriptionId) {
    whereOr.push({ stripeSubscriptionId: params.subscriptionId });
  }

  if (params.customerId) {
    whereOr.push({ stripeCustomerId: params.customerId });
  }

  if (!whereOr.length) {
    return null;
  }

  return prisma.company.findFirst({
    where: { OR: whereOr },
  });
};

router.post('/checkout', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(400).json({ error: 'Company membership required' });
  }

  if (!req.auth.lighthouse && !isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Only owners/admins can manage billing' });
  }

  const requestedTierId = typeof req.body?.tierId === 'string' ? req.body.tierId : null;
  if (requestedTierId && !Object.values(TIER_IDS).includes(requestedTierId as string)) {
    return res.status(400).json({ error: 'Invalid tier selection' });
  }

  const company = await prisma.company.findUnique({
    where: { id: req.auth.companyId },
  });

  if (!company) {
    return res.status(404).json({ error: 'Company not found' });
  }

  const activeStatuses: BillingStatus[] = [BillingStatus.ACTIVE, BillingStatus.TRIALING];
  if (activeStatuses.includes(company.billingStatus)) {
    return res.status(409).json({ error: 'Company subscription already active' });
  }

  const tierId = requestedTierId ?? company.tierId;
  const priceId = getStripePriceId(tierId);
  if (!priceId) {
    return res.status(500).json({ error: 'Stripe price is not configured for this tier' });
  }

  if (requestedTierId && requestedTierId !== company.tierId) {
    await prisma.company.update({
      where: { id: company.id },
      data: {
        tierId: requestedTierId,
      },
    });
  }

  const stripe = getStripe();

  const sessionParams: Stripe.Checkout.SessionCreateParams = {
    mode: 'subscription',
    line_items: [{ price: priceId, quantity: 1 }],
    metadata: {
      companyId: company.id,
      userId: req.auth.userId,
      tierId,
    },
    subscription_data: {
      metadata: {
        companyId: company.id,
        tierId,
      },
    },
    client_reference_id: company.id,
    success_url: STRIPE_SUCCESS_URL,
    cancel_url: STRIPE_CANCEL_URL,
  };

  if (company.stripeCustomerId) {
    sessionParams.customer = company.stripeCustomerId;
  } else {
    sessionParams.customer_email = req.auth.email;
  }

  const session = await stripe.checkout.sessions.create(sessionParams);

  await prisma.company.update({
    where: { id: company.id },
    data: {
      stripePriceId: priceId,
      billingStatus: BillingStatus.INCOMPLETE,
      billingUpdatedAt: new Date(),
    },
  });

  return res.json({ url: session.url });
});

router.post('/portal', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(400).json({ error: 'Company membership required' });
  }

  if (!req.auth.lighthouse && !isCompanyManager(req.auth.role)) {
    return res.status(403).json({ error: 'Only owners/admins can manage billing' });
  }

  const company = await prisma.company.findUnique({
    where: { id: req.auth.companyId },
    select: { stripeCustomerId: true },
  });

  if (!company?.stripeCustomerId) {
    return res.status(400).json({ error: 'Stripe customer not found' });
  }

  const stripe = getStripe();
  const session = await stripe.billingPortal.sessions.create({
    customer: company.stripeCustomerId,
    return_url: STRIPE_SUCCESS_URL,
  });

  return res.json({ url: session.url });
});

router.get('/status', authenticate, setLogConfig({ level: 'minimal' }), async (req, res) => {
  if (!req.auth) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!req.auth.companyId) {
    return res.status(400).json({ error: 'Company membership required' });
  }

  const company = await prisma.company.findUnique({
    where: { id: req.auth.companyId },
    select: {
      billingStatus: true,
      currentPeriodEnd: true,
      tierId: true,
    },
  });

  if (!company) {
    return res.status(404).json({ error: 'Company not found' });
  }

  return res.json(company);
});

export const billingWebhookHandler = async (req: Request, res: Response) => {
  const signature = req.headers['stripe-signature'];
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

  if (!signature || typeof signature !== 'string' || !webhookSecret) {
    return res.status(400).json({ error: 'Stripe webhook signature missing' });
  }

  let event: Stripe.Event;
  try {
    const stripe = getStripe();
    event = stripe.webhooks.constructEvent(req.body, signature, webhookSecret);
  } catch (error) {
    return res.status(400).json({ error: 'Invalid webhook signature', detail: (error as Error).message });
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session;
        const companyId = session.metadata?.companyId ?? session.client_reference_id ?? null;
        const subscriptionId = typeof session.subscription === 'string' ? session.subscription : null;
        const customerId = typeof session.customer === 'string' ? session.customer : null;

        if (companyId && subscriptionId && customerId) {
          const stripe = getStripe();
          const subscription = await stripe.subscriptions.retrieve(subscriptionId);
          const status = mapStripeStatus(subscription.status);
          const priceId = subscription.items.data[0]?.price?.id ?? null;

          await prisma.company.update({
            where: { id: companyId },
            data: {
              stripeCustomerId: customerId,
              stripeSubscriptionId: subscriptionId,
              stripePriceId: priceId ?? null,
              billingStatus: status,
              billingEmail: session.customer_details?.email ?? null,
              currentPeriodEnd:
                (subscription as Stripe.Subscription & { current_period_end?: number })
                  .current_period_end
                  ? new Date(
                      (subscription as Stripe.Subscription & { current_period_end?: number })
                        .current_period_end! * 1000,
                    )
                  : null,
              billingUpdatedAt: new Date(),
            },
          });
        }
        break;
      }
      case 'customer.subscription.updated': {
        const subscription = event.data.object as Stripe.Subscription;
        const company = await resolveCompanyForStripe({
          subscriptionId: subscription.id,
          customerId: typeof subscription.customer === 'string' ? subscription.customer : null,
        });
        if (company) {
          await prisma.company.update({
            where: { id: company.id },
            data: {
              stripeSubscriptionId: subscription.id,
              stripeCustomerId:
                typeof subscription.customer === 'string' ? subscription.customer : null,
              stripePriceId: subscription.items.data[0]?.price?.id ?? null,
              billingStatus: mapStripeStatus(subscription.status),
              currentPeriodEnd:
                (subscription as Stripe.Subscription & { current_period_end?: number })
                  .current_period_end
                  ? new Date(
                      (subscription as Stripe.Subscription & { current_period_end?: number })
                        .current_period_end! * 1000,
                    )
                  : null,
              billingUpdatedAt: new Date(),
            },
          });
        }
        break;
      }
      case 'customer.subscription.deleted': {
        const subscription = event.data.object as Stripe.Subscription;
        const company = await resolveCompanyForStripe({
          subscriptionId: subscription.id,
          customerId: typeof subscription.customer === 'string' ? subscription.customer : null,
        });
        if (company) {
          await prisma.company.update({
            where: { id: company.id },
            data: {
              billingStatus: BillingStatus.CANCELED,
              currentPeriodEnd: null,
              billingUpdatedAt: new Date(),
            },
          });
        }
        break;
      }
      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice & {
          subscription?: string | Stripe.Subscription | null;
        };
        const company = await resolveCompanyForStripe({
          subscriptionId: typeof invoice.subscription === 'string' ? invoice.subscription : null,
          customerId: typeof invoice.customer === 'string' ? invoice.customer : null,
        });
        if (company) {
          await prisma.company.update({
            where: { id: company.id },
            data: {
              billingStatus: BillingStatus.PAST_DUE,
              billingUpdatedAt: new Date(),
            },
          });
        }
        break;
      }
      case 'invoice.payment_succeeded': {
        const invoice = event.data.object as Stripe.Invoice & {
          subscription?: string | Stripe.Subscription | null;
        };
        const stripe = getStripe();
        const subscriptionId = typeof invoice.subscription === 'string' ? invoice.subscription : null;
        const company = await resolveCompanyForStripe({
          subscriptionId,
          customerId: typeof invoice.customer === 'string' ? invoice.customer : null,
        });
        if (company && subscriptionId) {
          const subscription = await stripe.subscriptions.retrieve(subscriptionId);
          await prisma.company.update({
            where: { id: company.id },
            data: {
              billingStatus: mapStripeStatus(subscription.status),
              currentPeriodEnd:
                (subscription as Stripe.Subscription & { current_period_end?: number })
                  .current_period_end
                  ? new Date(
                      (subscription as Stripe.Subscription & { current_period_end?: number })
                        .current_period_end! * 1000,
                    )
                  : null,
              billingUpdatedAt: new Date(),
            },
          });
        }
        break;
      }
      default:
        break;
    }
  } catch (error) {
    return res.status(500).json({ error: 'Failed to handle Stripe webhook', detail: (error as Error).message });
  }

  return res.json({ received: true });
};

export const billingRouter = router;
