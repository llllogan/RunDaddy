-- Migrate legacy GOD roles to ADMIN and remove GOD from the company-level role enum.

UPDATE `Membership` SET `role` = 'ADMIN' WHERE `role` = 'GOD';
UPDATE `InviteCode` SET `role` = 'ADMIN' WHERE `role` = 'GOD';

ALTER TABLE `Membership`
  MODIFY `role` ENUM('ADMIN', 'OWNER', 'PICKER') NOT NULL DEFAULT 'PICKER';

ALTER TABLE `InviteCode`
  MODIFY `role` ENUM('ADMIN', 'OWNER', 'PICKER') NOT NULL;

