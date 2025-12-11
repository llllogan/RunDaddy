-- Add optional label colour for SKUs to drive SwiftUI colour binding
ALTER TABLE `SKU`
  MODIFY COLUMN `labelColour` VARCHAR(191) NULL AFTER `weight`;
