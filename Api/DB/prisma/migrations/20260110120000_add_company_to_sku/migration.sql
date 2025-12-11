-- Add company ownership to SKUs so they belong to a single organisation
ALTER TABLE `SKU`
  ADD COLUMN `companyId` VARCHAR(191) NULL AFTER `id`;

-- Backfill company ownership based on the earliest run that used each SKU
WITH sku_company_usage AS (
  SELECT
    ci.skuId AS skuId,
    r.companyId AS companyId,
    MIN(COALESCE(r.scheduledFor, r.createdAt)) AS firstUsedAt
  FROM CoilItem ci
  JOIN PickEntry pe ON pe.coilItemId = ci.id
  JOIN Run r ON r.id = pe.runId
  WHERE r.companyId IS NOT NULL
  GROUP BY ci.skuId, r.companyId
),
sku_company_rankings AS (
  SELECT
    skuId,
    companyId,
    firstUsedAt,
    ROW_NUMBER() OVER (
      PARTITION BY skuId
      ORDER BY firstUsedAt ASC, companyId ASC
    ) AS companyRank
  FROM sku_company_usage
)
UPDATE SKU s
JOIN (
  SELECT skuId, companyId
  FROM sku_company_rankings
  WHERE companyRank = 1
) ranked ON ranked.skuId = s.id
SET s.companyId = ranked.companyId;

-- Relax global SKU code uniqueness so the same code can be used per company
ALTER TABLE `SKU` DROP INDEX `SKU_code_key`;

-- Index and enforce the relationship to the owning company
CREATE INDEX `SKU_companyId_idx` ON `SKU`(`companyId`);
CREATE INDEX `SKU_code_idx` ON `SKU`(`code`);
CREATE UNIQUE INDEX `SKU_companyId_code_key` ON `SKU`(`companyId`, `code`);

-- Index and enforce the relationship to the owning company
ALTER TABLE `SKU`
  ADD CONSTRAINT `SKU_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
