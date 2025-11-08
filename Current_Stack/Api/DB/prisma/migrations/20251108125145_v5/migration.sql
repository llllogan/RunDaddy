-- CreateTable
CREATE TABLE `RunLocationOrder` (
    `id` VARCHAR(191) NOT NULL,
    `runId` VARCHAR(191) NOT NULL,
    `locationId` VARCHAR(191) NULL,
    `position` INTEGER NOT NULL,

    INDEX `RunLocationOrder_runId_idx`(`runId`),
    INDEX `RunLocationOrder_locationId_idx`(`locationId`),
    INDEX `RunLocationOrder_runId_position_idx`(`runId`, `position`),
    UNIQUE INDEX `RunLocationOrder_runId_locationId_key`(`runId`, `locationId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `RunLocationOrder` ADD CONSTRAINT `RunLocationOrder_runId_fkey` FOREIGN KEY (`runId`) REFERENCES `Run`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `RunLocationOrder` ADD CONSTRAINT `RunLocationOrder_locationId_fkey` FOREIGN KEY (`locationId`) REFERENCES `Location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
