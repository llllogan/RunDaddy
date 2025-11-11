-- Seed SQL views for reporting and API helpers.

CREATE OR REPLACE VIEW v_user_memberships AS
SELECT
  u.id          AS user_id,
  u.email       AS user_email,
  u.firstName   AS user_first_name,
  u.lastName    AS user_last_name,
  u.phone       AS user_phone,
  u.createdAt   AS user_created_at,
  u.updatedAt   AS user_updated_at,
  u.role        AS user_role,
  m.role        AS membership_role,
  m.companyId   AS company_id,
  c.name        AS company_name
FROM `User` u
JOIN `Membership` m ON m.userId = u.id
JOIN `Company` c ON c.id = m.companyId;

CREATE OR REPLACE VIEW v_machine_details AS
SELECT
  mach.companyId    AS company_id,
  mach.id            AS machine_id,
  mach.code          AS machine_code,
  mach.description   AS machine_description,
  mach.machineTypeId AS machine_type_id,
  mt.name            AS machine_type_name,
  mt.description     AS machine_type_description,
  mach.locationId    AS location_id,
  loc.name           AS location_name,
  loc.address        AS location_address
FROM `Machine` mach
JOIN `MachineType` mt ON mt.id = mach.machineTypeId
LEFT JOIN `Location` loc ON loc.id = mach.locationId;

CREATE OR REPLACE VIEW v_coil_inventory AS
SELECT
  coil.id           AS coil_id,
  coil.code         AS coil_code,
  coil.machineId    AS machine_id,
  mach.companyId    AS company_id,
  mach.code         AS machine_code,
  ci.id             AS coil_item_id,
  ci.par            AS par_level,
  sku.id            AS sku_id,
  sku.code          AS sku_code,
  sku.name          AS sku_name,
  sku.type          AS sku_type,
  sku.isCheeseAndCrackers AS sku_is_cheese_and_crackers
FROM `Coil` coil
JOIN `Machine` mach ON mach.id = coil.machineId
LEFT JOIN `CoilItem` ci ON ci.coilId = coil.id
LEFT JOIN `SKU` sku ON sku.id = ci.skuId;

CREATE OR REPLACE VIEW v_run_overview AS
SELECT
  r.id                AS run_id,
  r.companyId         AS company_id,
  c.name              AS company_name,
  r.status            AS run_status,
  r.scheduledFor      AS scheduled_for,
  r.pickingStartedAt  AS picking_started_at,
  r.pickingEndedAt    AS picking_ended_at,
  r.createdAt         AS run_created_at,
  picker.id           AS picker_id,
  picker.firstName    AS picker_first_name,
  picker.lastName     AS picker_last_name,
  runner.id           AS runner_id,
  runner.firstName    AS runner_first_name,
  runner.lastName     AS runner_last_name
FROM `Run` r
JOIN `Company` c ON c.id = r.companyId
LEFT JOIN `User` picker ON picker.id = r.pickerId
LEFT JOIN `User` runner ON runner.id = r.runnerId;

CREATE OR REPLACE VIEW v_run_daily_locations AS
SELECT
  rov.run_id,
  rov.company_id,
  rov.company_name,
  DATE(rov.scheduled_for) AS scheduled_date,
  rov.scheduled_for,
  rov.run_status,
  rov.picking_started_at,
  rov.picking_ended_at,
  rov.run_created_at,
  rov.picker_id,
  rov.picker_first_name,
  rov.picker_last_name,
  rov.runner_id,
  rov.runner_first_name,
  rov.runner_last_name,
  COUNT(DISTINCT rl.location_id) AS location_count
FROM v_run_overview rov
LEFT JOIN (
  SELECT
    cb.runId        AS run_id,
    mach.locationId AS location_id
  FROM `ChocolateBox` cb
  JOIN `Machine` mach ON mach.id = cb.machineId
  WHERE mach.locationId IS NOT NULL

  UNION

  SELECT
    pe.runId        AS run_id,
    mach.locationId AS location_id
  FROM `PickEntry` pe
  JOIN `CoilItem` ci ON ci.id = pe.coilItemId
  JOIN `Coil` coil ON coil.id = ci.coilId
  JOIN `Machine` mach ON mach.id = coil.machineId
  WHERE mach.locationId IS NOT NULL
) rl ON rl.run_id = rov.run_id
GROUP BY
  rov.run_id,
  rov.company_id,
  rov.company_name,
  DATE(rov.scheduled_for),
  rov.scheduled_for,
  rov.run_status,
  rov.picking_started_at,
  rov.picking_ended_at,
  rov.run_created_at,
  rov.picker_id,
  rov.picker_first_name,
  rov.picker_last_name,
  rov.runner_id,
  rov.runner_first_name,
  rov.runner_last_name;

CREATE OR REPLACE VIEW v_run_pick_entries AS
SELECT
  re.id              AS pick_entry_id,
  re.runId           AS run_id,
  re.coilItemId      AS coil_item_id,
  re.count           AS picked_count,
  re.status          AS pick_status,
  re.pickedAt        AS picked_at,
  r.companyId        AS company_id,
  c.name             AS company_name,
  ci.coilId          AS coil_id,
  coil.machineId     AS machine_id,
  mach.code          AS machine_code,
  ci.skuId           AS sku_id,
  sku.code           AS sku_code,
  sku.name           AS sku_name
FROM `PickEntry` re
JOIN `Run` r ON r.id = re.runId
JOIN `Company` c ON c.id = r.companyId
JOIN `CoilItem` ci ON ci.id = re.coilItemId
JOIN `Coil` coil ON coil.id = ci.coilId
JOIN `Machine` mach ON mach.id = coil.machineId
JOIN `SKU` sku ON sku.id = ci.skuId;

CREATE OR REPLACE VIEW v_chocolate_box_details AS
SELECT
  cb.id           AS chocolate_box_id,
  cb.number       AS chocolate_box_number,
  cb.runId        AS run_id,
  cb.machineId    AS machine_id,
  mach.code       AS machine_code,
  r.companyId     AS company_id,
  c.name          AS company_name,
  r.status        AS run_status,
  r.scheduledFor  AS scheduled_for
FROM `ChocolateBox` cb
JOIN `Machine` mach ON mach.id = cb.machineId
JOIN `Run` r ON r.id = cb.runId
JOIN `Company` c ON c.id = r.companyId;

CREATE OR REPLACE VIEW v_user_refresh_tokens AS
SELECT
  rt.id        AS refresh_token_id,
  rt.userId    AS user_id,
  u.email      AS user_email,
  rt.tokenId   AS token_identifier,
  rt.expiresAt AS expires_at,
  rt.revoked   AS is_revoked,
  rt.createdAt AS created_at,
  rt.context   AS token_context
FROM `RefreshToken` rt
JOIN `User` u ON u.id = rt.userId;
