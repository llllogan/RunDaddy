-- Add note support for runs, machines, locations, and SKUs
CREATE TABLE `Note` (
  `id` VARCHAR(191) NOT NULL,
  `companyId` VARCHAR(191) NOT NULL,
  `runId` VARCHAR(191) NULL,
  `skuId` VARCHAR(191) NULL,
  `machineId` VARCHAR(191) NULL,
  `locationId` VARCHAR(191) NULL,
  `body` LONGTEXT NOT NULL,
  `createdBy` VARCHAR(191) NULL,
  `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE INDEX `Note_companyId_idx` ON `Note`(`companyId`);
CREATE INDEX `Note_runId_idx` ON `Note`(`runId`);
CREATE INDEX `Note_skuId_idx` ON `Note`(`skuId`);
CREATE INDEX `Note_machineId_idx` ON `Note`(`machineId`);
CREATE INDEX `Note_locationId_idx` ON `Note`(`locationId`);
CREATE INDEX `Note_createdAt_idx` ON `Note`(`createdAt`);

ALTER TABLE `Note`
  ADD CONSTRAINT `Note_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `Note_runId_fkey` FOREIGN KEY (`runId`) REFERENCES `Run`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `Note_skuId_fkey` FOREIGN KEY (`skuId`) REFERENCES `SKU`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `Note_machineId_fkey` FOREIGN KEY (`machineId`) REFERENCES `Machine`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `Note_locationId_fkey` FOREIGN KEY (`locationId`) REFERENCES `Location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `Note_createdBy_fkey` FOREIGN KEY (`createdBy`) REFERENCES `User`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
