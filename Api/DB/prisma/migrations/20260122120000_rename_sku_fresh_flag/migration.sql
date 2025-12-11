-- Rename cheese-and-crackers flag to the fresh/frozen indicator
ALTER TABLE `SKU`
  CHANGE COLUMN `isCheeseAndCrackers` `isFreshOrFrozen` BOOLEAN NOT NULL DEFAULT false;
