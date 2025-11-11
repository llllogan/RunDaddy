-- AlterTable
ALTER TABLE `SKU` ADD COLUMN `category` VARCHAR(191) NULL,
    ADD COLUMN `countNeededPointer` VARCHAR(191) NULL DEFAULT 'total';
