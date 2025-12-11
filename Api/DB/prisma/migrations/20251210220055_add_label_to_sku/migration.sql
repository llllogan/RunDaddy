-- Add the column so later migrations can reposition/resize it
ALTER TABLE `SKU` ADD COLUMN `labelColour` VARCHAR(191) NULL;
