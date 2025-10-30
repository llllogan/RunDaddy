-- Stored procedures supporting reporting and API data access.

DROP PROCEDURE IF EXISTS sp_health_check;
DROP PROCEDURE IF EXISTS sp_get_machine_details;
DROP PROCEDURE IF EXISTS sp_get_coil_inventory;
DROP PROCEDURE IF EXISTS sp_get_user_memberships;
DROP PROCEDURE IF EXISTS sp_get_user_refresh_tokens;
DROP PROCEDURE IF EXISTS sp_get_run_overview;
DROP PROCEDURE IF EXISTS sp_get_run_pick_entries;
DROP PROCEDURE IF EXISTS sp_get_chocolate_box_details;

CREATE PROCEDURE sp_health_check()
BEGIN
  SELECT 1 AS ok;
END;

CREATE PROCEDURE sp_get_machine_details(
  IN p_company_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  SELECT *
  FROM v_machine_details
  WHERE company_id = p_company_id
  ORDER BY machine_code ASC;
END;

CREATE PROCEDURE sp_get_coil_inventory(
  IN p_company_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  IN p_machine_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  IF p_machine_id IS NULL OR p_machine_id = '' THEN
    SELECT *
    FROM v_coil_inventory
    WHERE company_id = p_company_id
    ORDER BY machine_code ASC, coil_code ASC;
  ELSE
    SELECT *
    FROM v_coil_inventory
    WHERE company_id = p_company_id
      AND machine_id = p_machine_id
    ORDER BY machine_code ASC, coil_code ASC;
  END IF;
END;

CREATE PROCEDURE sp_get_user_memberships(
  IN p_company_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  SELECT *
  FROM v_user_memberships
  WHERE company_id = p_company_id
  ORDER BY user_last_name ASC, user_first_name ASC;
END;

CREATE PROCEDURE sp_get_user_refresh_tokens(
  IN p_user_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  SELECT *
  FROM v_user_refresh_tokens
  WHERE user_id = p_user_id;
END;

CREATE PROCEDURE sp_get_run_overview(
  IN p_company_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  IN p_status VARCHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  IF p_status IS NULL OR p_status = '' THEN
    SELECT *
    FROM v_run_overview
    WHERE company_id = p_company_id
    ORDER BY scheduled_for DESC, run_created_at DESC;
  ELSE
    SELECT *
    FROM v_run_overview
    WHERE company_id = p_company_id
      AND run_status = p_status COLLATE utf8mb4_unicode_ci
    ORDER BY scheduled_for DESC, run_created_at DESC;
  END IF;
END;

CREATE PROCEDURE sp_get_run_pick_entries(
  IN p_company_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  IN p_run_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  IF p_run_id IS NULL OR p_run_id = '' THEN
    SELECT *
    FROM v_run_pick_entries
    WHERE company_id = p_company_id
    ORDER BY run_id DESC, pick_entry_id ASC;
  ELSE
    SELECT *
    FROM v_run_pick_entries
    WHERE company_id = p_company_id
      AND run_id = p_run_id
    ORDER BY run_id DESC, pick_entry_id ASC;
  END IF;
END;

CREATE PROCEDURE sp_get_chocolate_box_details(
  IN p_company_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  IN p_run_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  IF p_run_id IS NULL OR p_run_id = '' THEN
    SELECT *
    FROM v_chocolate_box_details
    WHERE company_id = p_company_id
    ORDER BY run_id DESC, chocolate_box_number ASC;
  ELSE
    SELECT *
    FROM v_chocolate_box_details
    WHERE company_id = p_company_id
      AND run_id = p_run_id
    ORDER BY run_id DESC, chocolate_box_number ASC;
  END IF;
END;
