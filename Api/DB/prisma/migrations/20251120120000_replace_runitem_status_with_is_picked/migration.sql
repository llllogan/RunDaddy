-- Add boolean flag for pick completion
ALTER TABLE `PickEntry` ADD COLUMN `isPicked` BOOLEAN NOT NULL DEFAULT 0 AFTER `total`;

-- Preserve existing status values by mapping PICKED -> true, others -> false
UPDATE `PickEntry` SET `isPicked` = IF(`status` = 'PICKED', 1, 0);

-- Drop the old status column
ALTER TABLE `PickEntry` DROP COLUMN `status`;
