/*
  Warnings:

  - The values [PICKED,IN_PROGRESS,COMPLETED,CANCELLED,HISTORICAL] on the enum `Run_status` will be removed. If these variants are still used in the database, this will fail.

*/
-- AlterTable
ALTER TABLE `Run` MODIFY `status` ENUM('CREATED', 'PICKING', 'READY') NOT NULL DEFAULT 'CREATED';
