-- Add an override count column for pick entries
ALTER TABLE `PickEntry`
  ADD COLUMN `override` INT NULL;
