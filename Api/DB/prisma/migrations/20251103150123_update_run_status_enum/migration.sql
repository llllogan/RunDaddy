-- Update existing data to match new enum values
UPDATE `Run` SET `status` = 'CREATED' WHERE `status` = 'DRAFT';
UPDATE `Run` SET `status` = 'CREATED' WHERE `status` = 'READY';
-- Note: SCHEDULED status is kept as-is since it's still valid

-- AlterTable
ALTER TABLE `Run` MODIFY COLUMN `status` ENUM('CREATED', 'PICKING', 'PICKED', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'HISTORICAL') NOT NULL DEFAULT 'CREATED';