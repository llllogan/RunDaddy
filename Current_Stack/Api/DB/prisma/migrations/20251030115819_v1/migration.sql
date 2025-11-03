-- CreateTable
CREATE TABLE `User` (
    `id` VARCHAR(191) NOT NULL,
    `email` VARCHAR(191) NOT NULL,
    `password` VARCHAR(191) NOT NULL,
    `firstName` VARCHAR(191) NOT NULL,
    `lastName` VARCHAR(191) NOT NULL,
    `role` ENUM('ADMIN', 'OWNER', 'PICKER') NOT NULL DEFAULT 'PICKER',
    `phone` VARCHAR(191) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,
    `defaultMembershipId` VARCHAR(191) NULL,

    UNIQUE INDEX `User_email_key`(`email`),
    UNIQUE INDEX `User_defaultMembershipId_key`(`defaultMembershipId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `Membership` (
    `id` VARCHAR(191) NOT NULL,
    `userId` VARCHAR(191) NOT NULL,
    `companyId` VARCHAR(191) NOT NULL,
    `role` ENUM('ADMIN', 'OWNER', 'PICKER') NOT NULL DEFAULT 'PICKER',

    INDEX `Membership_userId_idx`(`userId`),
    INDEX `Membership_companyId_idx`(`companyId`),
    UNIQUE INDEX `Membership_userId_companyId_key`(`userId`, `companyId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `Company` (
    `id` VARCHAR(191) NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,

    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `MachineType` (
    `id` VARCHAR(191) NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `description` VARCHAR(191) NULL,

    UNIQUE INDEX `MachineType_name_key`(`name`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `Location` (
    `id` VARCHAR(191) NOT NULL,
    `companyId` VARCHAR(191) NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `address` VARCHAR(191) NULL,

    INDEX `Location_companyId_idx`(`companyId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `Machine` (
    `id` VARCHAR(191) NOT NULL,
    `companyId` VARCHAR(191) NOT NULL,
    `code` VARCHAR(191) NOT NULL,
    `description` VARCHAR(191) NULL,
    `machineTypeId` VARCHAR(191) NOT NULL,
    `locationId` VARCHAR(191) NULL,

    INDEX `Machine_code_idx`(`code`),
    INDEX `Machine_machineTypeId_idx`(`machineTypeId`),
    INDEX `Machine_locationId_idx`(`locationId`),
    INDEX `Machine_companyId_idx`(`companyId`),
    UNIQUE INDEX `Machine_companyId_code_key`(`companyId`, `code`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `Coil` (
    `id` VARCHAR(191) NOT NULL,
    `code` VARCHAR(191) NOT NULL,
    `machineId` VARCHAR(191) NOT NULL,

    INDEX `Coil_machineId_idx`(`machineId`),
    UNIQUE INDEX `Coil_machineId_code_key`(`machineId`, `code`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `CoilItem` (
    `id` VARCHAR(191) NOT NULL,
    `coilId` VARCHAR(191) NOT NULL,
    `skuId` VARCHAR(191) NOT NULL,
    `par` INTEGER NOT NULL,

    INDEX `CoilItem_coilId_idx`(`coilId`),
    INDEX `CoilItem_skuId_idx`(`skuId`),
    UNIQUE INDEX `CoilItem_coilId_skuId_key`(`coilId`, `skuId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `SKU` (
    `id` VARCHAR(191) NOT NULL,
    `code` VARCHAR(191) NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `type` VARCHAR(191) NOT NULL,
    `isCheeseAndCrackers` BOOLEAN NOT NULL DEFAULT false,

    UNIQUE INDEX `SKU_code_key`(`code`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `Run` (
    `id` VARCHAR(191) NOT NULL,
    `pickerId` VARCHAR(191) NULL,
    `runnerId` VARCHAR(191) NULL,
    `companyId` VARCHAR(191) NOT NULL,
    `status` ENUM('DRAFT', 'PICKING', 'READY', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'HISTORICAL') NOT NULL DEFAULT 'DRAFT',
    `pickingStartedAt` DATETIME(3) NULL,
    `pickingEndedAt` DATETIME(3) NULL,
    `scheduledFor` DATETIME(3) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `Run_pickerId_idx`(`pickerId`),
    INDEX `Run_runnerId_idx`(`runnerId`),
    INDEX `Run_companyId_idx`(`companyId`),
    INDEX `Run_companyId_scheduledFor_idx`(`companyId`, `scheduledFor`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `PickEntry` (
    `id` VARCHAR(191) NOT NULL,
    `runId` VARCHAR(191) NOT NULL,
    `coilItemId` VARCHAR(191) NOT NULL,
    `count` INTEGER NOT NULL,
    `status` ENUM('PENDING', 'PICKED', 'SKIPPED') NOT NULL DEFAULT 'PENDING',
    `pickedAt` DATETIME(3) NULL,

    INDEX `PickEntry_runId_idx`(`runId`),
    INDEX `PickEntry_coilItemId_idx`(`coilItemId`),
    UNIQUE INDEX `PickEntry_runId_coilItemId_key`(`runId`, `coilItemId`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `RunImport` (
    `id` VARCHAR(191) NOT NULL,
    `companyId` VARCHAR(191) NOT NULL,
    `sheetName` VARCHAR(191) NOT NULL,
    `locationName` VARCHAR(191) NOT NULL,
    `address` VARCHAR(191) NULL,
    `runDate` DATETIME(3) NULL,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `RunImport_companyId_idx`(`companyId`),
    INDEX `RunImport_companyId_createdAt_idx`(`companyId`, `createdAt`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `RunImportMachine` (
    `id` VARCHAR(191) NOT NULL,
    `runImportId` VARCHAR(191) NOT NULL,
    `machineCode` VARCHAR(191) NOT NULL,
    `machineName` VARCHAR(191) NULL,
    `category` VARCHAR(191) NULL,
    `machineTypeName` VARCHAR(191) NULL,
    `runDate` DATETIME(3) NULL,

    INDEX `RunImportMachine_runImportId_idx`(`runImportId`),
    INDEX `RunImportMachine_machineCode_idx`(`machineCode`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `RunImportCoilItem` (
    `id` VARCHAR(191) NOT NULL,
    `runImportMachineId` VARCHAR(191) NOT NULL,
    `coilCode` VARCHAR(191) NULL,
    `skuCode` VARCHAR(191) NULL,
    `skuName` VARCHAR(191) NULL,
    `skuType` VARCHAR(191) NULL,
    `short` INTEGER NULL,
    `inventoryFlag` VARCHAR(191) NULL,
    `spoil` INTEGER NULL,
    `inventoryCount` INTEGER NULL,
    `current` INTEGER NULL,
    `par` INTEGER NULL,
    `need` INTEGER NULL,
    `forecast` INTEGER NULL,
    `total` INTEGER NULL,
    `notes` VARCHAR(191) NULL,

    INDEX `RunImportCoilItem_runImportMachineId_idx`(`runImportMachineId`),
    INDEX `RunImportCoilItem_coilCode_idx`(`coilCode`),
    INDEX `RunImportCoilItem_skuCode_idx`(`skuCode`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `ChocolateBox` (
    `id` VARCHAR(191) NOT NULL,
    `runId` VARCHAR(191) NOT NULL,
    `machineId` VARCHAR(191) NOT NULL,
    `number` INTEGER NOT NULL,

    INDEX `ChocolateBox_runId_idx`(`runId`),
    INDEX `ChocolateBox_machineId_idx`(`machineId`),
    UNIQUE INDEX `ChocolateBox_runId_number_key`(`runId`, `number`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `RefreshToken` (
    `id` VARCHAR(191) NOT NULL,
    `userId` VARCHAR(191) NOT NULL,
    `tokenId` VARCHAR(191) NOT NULL,
    `expiresAt` DATETIME(3) NOT NULL,
    `revoked` BOOLEAN NOT NULL DEFAULT false,
    `createdAt` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updatedAt` DATETIME(3) NOT NULL,
    `context` ENUM('WEB', 'APP') NOT NULL DEFAULT 'WEB',

    UNIQUE INDEX `RefreshToken_tokenId_key`(`tokenId`),
    INDEX `RefreshToken_userId_idx`(`userId`),
    INDEX `RefreshToken_context_idx`(`context`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `User` ADD CONSTRAINT `User_defaultMembershipId_fkey` FOREIGN KEY (`defaultMembershipId`) REFERENCES `Membership`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Membership` ADD CONSTRAINT `Membership_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Membership` ADD CONSTRAINT `Membership_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Location` ADD CONSTRAINT `Location_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Machine` ADD CONSTRAINT `Machine_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Machine` ADD CONSTRAINT `Machine_machineTypeId_fkey` FOREIGN KEY (`machineTypeId`) REFERENCES `MachineType`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Machine` ADD CONSTRAINT `Machine_locationId_fkey` FOREIGN KEY (`locationId`) REFERENCES `Location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Coil` ADD CONSTRAINT `Coil_machineId_fkey` FOREIGN KEY (`machineId`) REFERENCES `Machine`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `CoilItem` ADD CONSTRAINT `CoilItem_coilId_fkey` FOREIGN KEY (`coilId`) REFERENCES `Coil`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `CoilItem` ADD CONSTRAINT `CoilItem_skuId_fkey` FOREIGN KEY (`skuId`) REFERENCES `SKU`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Run` ADD CONSTRAINT `Run_pickerId_fkey` FOREIGN KEY (`pickerId`) REFERENCES `User`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Run` ADD CONSTRAINT `Run_runnerId_fkey` FOREIGN KEY (`runnerId`) REFERENCES `User`(`id`) ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `Run` ADD CONSTRAINT `Run_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `PickEntry` ADD CONSTRAINT `PickEntry_runId_fkey` FOREIGN KEY (`runId`) REFERENCES `Run`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `PickEntry` ADD CONSTRAINT `PickEntry_coilItemId_fkey` FOREIGN KEY (`coilItemId`) REFERENCES `CoilItem`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `RunImport` ADD CONSTRAINT `RunImport_companyId_fkey` FOREIGN KEY (`companyId`) REFERENCES `Company`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `RunImportMachine` ADD CONSTRAINT `RunImportMachine_runImportId_fkey` FOREIGN KEY (`runImportId`) REFERENCES `RunImport`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `RunImportCoilItem` ADD CONSTRAINT `RunImportCoilItem_runImportMachineId_fkey` FOREIGN KEY (`runImportMachineId`) REFERENCES `RunImportMachine`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `ChocolateBox` ADD CONSTRAINT `ChocolateBox_runId_fkey` FOREIGN KEY (`runId`) REFERENCES `Run`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `ChocolateBox` ADD CONSTRAINT `ChocolateBox_machineId_fkey` FOREIGN KEY (`machineId`) REFERENCES `Machine`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `RefreshToken` ADD CONSTRAINT `RefreshToken_userId_fkey` FOREIGN KEY (`userId`) REFERENCES `User`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
