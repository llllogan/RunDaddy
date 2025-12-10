-- Add optional label colour for SKUs to drive SwiftUI colour binding
ALTER TABLE `SKU`
  ADD COLUMN `labelColour` VARCHAR(32) NULL AFTER `weight`;
