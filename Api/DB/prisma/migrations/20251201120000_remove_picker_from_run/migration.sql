-- Drop picker relation from Run
ALTER TABLE `Run` DROP FOREIGN KEY `Run_pickerId_fkey`;
ALTER TABLE `Run` DROP INDEX `Run_pickerId_idx`;
ALTER TABLE `Run` DROP COLUMN `pickerId`;
