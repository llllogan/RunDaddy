-- Add timeZone column to Company so we can track each organization's preferred timezone
ALTER TABLE `Company`
  ADD COLUMN `timeZone` VARCHAR(191) NULL;
