-- AlterTable
ALTER TABLE `Company`
  ADD COLUMN `showColdChest` BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN `showChocolateBoxes` BOOLEAN NOT NULL DEFAULT true;
