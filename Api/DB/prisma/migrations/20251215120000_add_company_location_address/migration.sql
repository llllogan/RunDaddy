-- Add address field to companies for storing a primary location
ALTER TABLE `Company`
  ADD COLUMN `location` VARCHAR(191) NULL AFTER `updatedAt`;
