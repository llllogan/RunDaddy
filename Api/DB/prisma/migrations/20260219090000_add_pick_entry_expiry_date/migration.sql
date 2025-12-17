-- Add persisted expiry date to PickEntry to avoid computing it on-demand for every expiries request.

ALTER TABLE `PickEntry`
  ADD COLUMN `expiryDate` VARCHAR(10) NULL,
  ADD INDEX `PickEntry_expiryDate_idx` (`expiryDate`),
  ADD INDEX `PickEntry_coilItemId_expiryDate_idx` (`coilItemId`, `expiryDate`);

-- Backfill expiryDate for existing rows using the run date + SKU expiryDays in the owning company's timezone.
UPDATE `PickEntry` pe
  INNER JOIN `Run` r ON r.id = pe.runId
  INNER JOIN `Company` co ON co.id = r.companyId
  INNER JOIN `CoilItem` ci ON ci.id = pe.coilItemId
  INNER JOIN `SKU` s ON s.id = ci.skuId
SET pe.expiryDate = DATE_FORMAT(
  DATE_ADD(CONVERT_TZ(r.scheduledFor, 'UTC', COALESCE(co.timeZone, 'UTC')), INTERVAL (s.expiryDays - 1) DAY),
  '%Y-%m-%d'
)
WHERE pe.expiryDate IS NULL
  AND r.scheduledFor IS NOT NULL
  AND s.expiryDays > 0;

