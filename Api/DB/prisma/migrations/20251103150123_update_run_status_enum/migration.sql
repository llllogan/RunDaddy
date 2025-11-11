-- Update existing data to match new enum values
UPDATE `Run` SET `status` = 'CREATED' WHERE `status` = 'DRAFT';
UPDATE `Run` SET `status` = 'CREATED' WHERE `status` = 'READY';
UPDATE `Run` SET `status` = 'CREATED' WHERE `status` = 'SCHEDULED';

-- AlterTable
ALTER TABLE `Run` MODIFY COLUMN `status` ENUM('CREATED', 'PICKING', 'PICKED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'HISTORICAL') NOT NULL DEFAULT 'CREATED';

-- Ensure the default is set correctly
ALTER TABLE `Run` ALTER COLUMN `status` SET DEFAULT 'CREATED';