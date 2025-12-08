-- Allow nulls on legacy role enum so we can reset existing values
ALTER TABLE `User`
  MODIFY `role` ENUM('GOD', 'ADMIN', 'OWNER', 'PICKER') NULL DEFAULT NULL;

-- Company-level roles now live on memberships; clear old user roles
UPDATE `User` SET `role` = NULL;

-- Switch to the account-level role enum
ALTER TABLE `User`
  MODIFY `role` ENUM('LIGHTHOUSE') NULL DEFAULT NULL;
