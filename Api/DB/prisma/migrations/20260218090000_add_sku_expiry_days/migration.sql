-- Add SKU expiry tracking (days until expiry, relative to run scheduled day)
ALTER TABLE `SKU`
  ADD COLUMN `expiryDays` INTEGER NOT NULL DEFAULT 0;

