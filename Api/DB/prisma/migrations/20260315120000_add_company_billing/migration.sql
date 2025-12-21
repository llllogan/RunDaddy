-- Add billing fields to companies
ALTER TABLE `Company`
  ADD COLUMN `billingStatus` ENUM('ACTIVE', 'TRIALING', 'INCOMPLETE', 'PAST_DUE', 'UNPAID', 'CANCELED') NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN `stripeCustomerId` VARCHAR(191) NULL,
  ADD COLUMN `stripeSubscriptionId` VARCHAR(191) NULL,
  ADD COLUMN `stripePriceId` VARCHAR(191) NULL,
  ADD COLUMN `billingEmail` VARCHAR(191) NULL,
  ADD COLUMN `currentPeriodEnd` DATETIME(3) NULL,
  ADD COLUMN `billingUpdatedAt` DATETIME(3) NULL;

CREATE INDEX `Company_stripeCustomerId_idx` ON `Company`(`stripeCustomerId`);
CREATE INDEX `Company_stripeSubscriptionId_idx` ON `Company`(`stripeSubscriptionId`);
