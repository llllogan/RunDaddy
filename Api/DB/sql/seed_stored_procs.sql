-- Stored procedures supporting reporting and API data access.

DROP PROCEDURE IF EXISTS sp_health_check;
DROP PROCEDURE IF EXISTS sp_get_machine_details;
DROP PROCEDURE IF EXISTS sp_get_coil_inventory;
DROP PROCEDURE IF EXISTS sp_get_user_memberships;
DROP PROCEDURE IF EXISTS sp_get_user_refresh_tokens;
DROP PROCEDURE IF EXISTS sp_get_run_overview;
DROP PROCEDURE IF EXISTS sp_get_run_pick_entries;
DROP PROCEDURE IF EXISTS sp_get_chocolate_box_details;
DROP PROCEDURE IF EXISTS sp_get_company_members_by_ids;
DROP PROCEDURE IF EXISTS sp_assign_run_participant;
DROP PROCEDURE IF EXISTS sp_get_runs_by_company;


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

CREATE PROCEDURE sp_get_company_members_by_ids(
  IN p_company_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  IN p_user_ids_csv TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  IF p_user_ids_csv IS NULL OR p_user_ids_csv = '' THEN
    SELECT *
    FROM v_user_memberships
    WHERE 1 = 0;
  ELSE
    SELECT *
    FROM v_user_memberships
    WHERE company_id = p_company_id
      AND FIND_IN_SET(user_id, p_user_ids_csv) > 0
    ORDER BY user_last_name ASC, user_first_name ASC;
  END IF;
END;

CREATE PROCEDURE sp_assign_run_participant(
  IN p_company_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  IN p_run_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  IN p_user_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  IN p_participant_role VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  DECLARE v_role VARCHAR(16) DEFAULT UPPER(p_participant_role);
  DECLARE v_effective_user_id VARCHAR(191);

  SET v_effective_user_id = NULLIF(p_user_id, '');

  IF v_role = 'RUNNER' THEN
    UPDATE `Run`
    SET runnerId = v_effective_user_id
    WHERE id = p_run_id
      AND companyId = p_company_id;
  END IF;

  SELECT
    r.id               AS run_id,
    r.companyId        AS company_id,
    r.status           AS run_status,
    r.runnerId         AS runner_id,
    runner.firstName   AS runner_first_name,
    runner.lastName    AS runner_last_name,
    r.pickingStartedAt AS picking_started_at,
    r.pickingEndedAt   AS picking_ended_at,
    r.scheduledFor     AS scheduled_for,
    r.createdAt        AS run_created_at
  FROM `Run` r
  LEFT JOIN `User` runner ON runner.id = r.runnerId
  WHERE r.id = p_run_id
    AND r.companyId = p_company_id;
END;

CREATE PROCEDURE sp_get_runs_by_company(
  IN p_company_id VARCHAR(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  IN p_status VARCHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
  IF p_status IS NULL OR p_status = '' THEN
    SELECT
      id,
      runnerId,
      companyId,
      status,
      pickingStartedAt,
      pickingEndedAt,
      scheduledFor,
      createdAt
    FROM `Run`
    WHERE companyId = p_company_id
    ORDER BY createdAt DESC;
  ELSE
    SELECT
      id,
      runnerId,
      companyId,
      status,
      pickingStartedAt,
      pickingEndedAt,
      scheduledFor,
      createdAt
    FROM `Run`
    WHERE companyId = p_company_id
      AND status = p_status COLLATE utf8mb4_unicode_ci
    ORDER BY createdAt DESC;
  END IF;
END;
