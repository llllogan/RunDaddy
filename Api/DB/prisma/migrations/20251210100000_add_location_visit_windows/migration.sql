-- Add time window and dwell time metadata to locations
ALTER TABLE `Location`
  ADD COLUMN `openingTimeMinutes` INT NULL AFTER `address`,
  ADD COLUMN `closingTimeMinutes` INT NULL AFTER `openingTimeMinutes`,
  ADD COLUMN `dwellTimeMinutes` INT NULL AFTER `closingTimeMinutes`;
