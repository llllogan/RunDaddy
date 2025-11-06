/*
  Warnings:

  - You are about to drop the `RunImport` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `RunImportCoilItem` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `RunImportMachine` table. If the table is not empty, all the data it contains will be lost.

*/
-- DropForeignKey
ALTER TABLE `RunImport` DROP FOREIGN KEY `RunImport_companyId_fkey`;

-- DropForeignKey
ALTER TABLE `RunImportCoilItem` DROP FOREIGN KEY `RunImportCoilItem_runImportMachineId_fkey`;

-- DropForeignKey
ALTER TABLE `RunImportMachine` DROP FOREIGN KEY `RunImportMachine_runImportId_fkey`;

-- DropTable
DROP TABLE `RunImport`;

-- DropTable
DROP TABLE `RunImportCoilItem`;

-- DropTable
DROP TABLE `RunImportMachine`;
