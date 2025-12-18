-- Add pick entry expiry overrides to support multiple expiry dates within a single pick entry.

CREATE TABLE `PickEntryExpiryOverride` (
    `id` VARCHAR(191) NOT NULL,
    `pickEntryId` VARCHAR(191) NOT NULL,
    `expiryDate` VARCHAR(10) NOT NULL,
    `quantity` INTEGER NOT NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    UNIQUE INDEX `PickEntryExpiryOverride_pickEntryId_expiryDate_key`(`pickEntryId`, `expiryDate`),
    INDEX `PickEntryExpiryOverride_pickEntryId_idx`(`pickEntryId`),
    INDEX `PickEntryExpiryOverride_expiryDate_idx`(`expiryDate`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE `PickEntryExpiryOverride`
    ADD CONSTRAINT `PickEntryExpiryOverride_pickEntryId_fkey`
    FOREIGN KEY (`pickEntryId`) REFERENCES `PickEntry`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

