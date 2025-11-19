-- CreateTable
CREATE TABLE `TierConsts` (
    `id` VARCHAR(191) NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `maxOwners` INTEGER NOT NULL,
    `maxAdmins` INTEGER NOT NULL,
    `maxPickers` INTEGER NOT NULL,
    `canBreakDownRun` BOOLEAN NOT NULL DEFAULT false,

    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
