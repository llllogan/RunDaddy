-- AlterTable
ALTER TABLE `Company` ADD COLUMN `tierId` VARCHAR(191) NULL;

-- Seed tier rows required for the new foreign key
INSERT INTO `TierConsts` (`id`, `name`, `maxOwners`, `maxAdmins`, `maxPickers`, `canBreakDownRun`)
VALUES
  ('tier-individual', 'Individual', 1, 0, 0, false),
  ('tier-business', 'Business', 1, 1, 2, true),
  ('tier-enterprise-10', 'Enterprise 10', 1, 2, 10, true)
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`),
  `maxOwners` = VALUES(`maxOwners`),
  `maxAdmins` = VALUES(`maxAdmins`),
  `maxPickers` = VALUES(`maxPickers`),
  `canBreakDownRun` = VALUES(`canBreakDownRun`);

-- Backfill existing companies
UPDATE `Company` SET `tierId` = 'tier-individual' WHERE `tierId` IS NULL;

-- AlterTable
ALTER TABLE `Company` MODIFY `tierId` VARCHAR(191) NOT NULL;

-- CreateIndex
CREATE INDEX `Company_tierId_idx` ON `Company`(`tierId`);

-- AddForeignKey
ALTER TABLE `Company` ADD CONSTRAINT `Company_tierId_fkey` FOREIGN KEY (`tierId`) REFERENCES `TierConsts`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
