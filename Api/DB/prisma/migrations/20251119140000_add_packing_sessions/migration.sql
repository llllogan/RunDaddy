-- CreateTable
CREATE TABLE `PackingSession` (
    `id` VARCHAR(191) NOT NULL,
    `runId` VARCHAR(191) NOT NULL,
    `userId` VARCHAR(191) NOT NULL,
    `startedAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `finishedAt` DATETIME(3) NULL,
    `status` ENUM('STARTED', 'FINISHED', 'ABANDONED') NOT NULL DEFAULT 'STARTED',

    INDEX `PackingSession_runId_idx`(`runId`),
    INDEX `PackingSession_userId_idx`(`userId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AlterTable
ALTER TABLE `PickEntry` ADD COLUMN `packingSessionId` VARCHAR(191) NULL;

-- CreateIndex
CREATE INDEX `PickEntry_packingSessionId_idx` ON `PickEntry`(`packingSessionId`);

-- AddForeignKey
ALTER TABLE `PackingSession` ADD CONSTRAINT `PackingSession_runId_fkey` FOREIGN KEY (`runId`) REFERENCES `Run`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `PackingSession` ADD CONSTRAINT `PackingSession_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `PickEntry` ADD CONSTRAINT `PickEntry_packingSessionId_fkey` FOREIGN KEY (`packingSessionId`) REFERENCES `PackingSession`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;
