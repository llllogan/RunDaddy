export type PlanTier = {
  id: string;
  name: string;
  price: string;
  description: string;
  features: string[];
  badge?: string;
};

export const planTiers: PlanTier[] = [
  {
    id: 'tier-individual',
    name: 'Individual',
    price: '$60',
    description: 'Best for solo operators getting started.',
    features: ['1 owner seat', 'Run & inventory tracking', 'Location insights', 'Email support'],
  },
  {
    id: 'tier-business',
    name: 'Business',
    price: '$100',
    description: 'Built for growing teams that need coordination.',
    badge: 'Most popular',
    features: [
      '1 owner + 1 admin',
      '2 picker/driver seats',
      'Team invites & roles',
      'Operational reporting',
    ],
  },
  {
    id: 'tier-enterprise-10',
    name: 'Enterprise 10',
    price: '$200',
    description: 'Scale operations across more locations.',
    features: [
      '1 owner + 1 admin',
      '10 picker/driver seats',
      'Advanced reporting',
      'Priority support',
    ],
  },
];
