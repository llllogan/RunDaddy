-- CreateTable
CREATE TABLE `ExpiryIgnore` (
    `id` VARCHAR(191) NOT NULL,
    `companyId` VARCHAR(191) NOT NULL,
    `coilItemId` VARCHAR(191) NOT NULL,
    `expiryDate` VARCHAR(10) NOT NULL,
    `quantity` INTEGER NOT NULL,
    `ignoredAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `createdBy` VARCHAR(191) NULL,

    UNIQUE INDEX `ExpiryIgnore_companyId_coilItemId_expiryDate_key`(`companyId`, `coilItemId`, `expiryDate`),
    INDEX `ExpiryIgnore_companyId_expiryDate_idx`(`companyId`, `expiryDate`),
    INDEX `ExpiryIgnore_coilItemId_expiryDate_idx`(`coilItemId`, `expiryDate`),
    INDEX `ExpiryIgnore_createdBy_idx`(`createdBy`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `ExpiryIgnore` ADD CONSTRAINT `ExpiryIgnore_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `ExpiryIgnore` ADD CONSTRAINT `ExpiryIgnore_coilItemId_fkey` FOREIGN KEY (`coilItemId`) REFERENCES `CoilItem`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `ExpiryIgnore` ADD CONSTRAINT `ExpiryIgnore_createdBy_fkey` FOREIGN KEY (`createdBy`) REFERENCES `User`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
