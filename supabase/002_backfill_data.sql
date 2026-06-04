-- =============================================================================
-- KLYCH Data Backfill
-- Run AFTER 001_production_sync.sql
-- Seeds departments, invite codes, and user defaults for existing organizations.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Default departments for every organization without any
-- ---------------------------------------------------------------------------
INSERT INTO departments (organization_id, name)
SELECT o.id, d.name
FROM organizations o
CROSS JOIN (
  VALUES
    ('Headquarters'),
    ('Medics'),
    ('Drivers'),
    ('Logistics'),
    ('Communications'),
    ('Evacuation')
) AS d(name)
WHERE NOT EXISTS (
  SELECT 1 FROM departments dep WHERE dep.organization_id = o.id
);

-- ---------------------------------------------------------------------------
-- 2. Assign existing users without department → Headquarters
-- ---------------------------------------------------------------------------
UPDATE users u
SET department_id = hq.id
FROM departments hq
WHERE u.department_id IS NULL
  AND hq.organization_id = u.organization_id
  AND hq.name = 'Headquarters'
  AND hq.is_archived = false;

-- ---------------------------------------------------------------------------
-- 3. Normalize status for existing users
-- ---------------------------------------------------------------------------
UPDATE users
SET status = 'available'
WHERE status IS NULL OR status NOT IN (
  'available', 'on_duty', 'deployed', 'vacation', 'unavailable'
);

UPDATE users
SET is_disabled = false
WHERE is_disabled IS NULL;

UPDATE users
SET last_activity_at = COALESCE(last_activity_at, created_at, now())
WHERE last_activity_at IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Normalize authorization roles (legacy medic/driver → member)
-- ---------------------------------------------------------------------------
UPDATE users
SET role = 'member', permission = 'member'
WHERE role IN ('medic', 'driver')
   OR permission IN ('medic', 'driver');

-- ---------------------------------------------------------------------------
-- 5. Ensure member invite exists for every organization
-- ---------------------------------------------------------------------------
INSERT INTO invites (organization_id, code, permission)
SELECT o.id,
       lpad((floor(random() * 900000) + 100000)::text, 6, '0'),
       'member'
FROM organizations o
WHERE NOT EXISTS (
  SELECT 1 FROM invites i
  WHERE i.organization_id = o.id
    AND lower(coalesce(i.permission, 'member')) NOT IN ('leader', 'admin')
);

-- ---------------------------------------------------------------------------
-- 6. Ensure leader invite exists for every organization
-- ---------------------------------------------------------------------------
INSERT INTO invites (organization_id, code, permission)
SELECT o.id,
       lpad((floor(random() * 900000) + 100000)::text, 6, '0'),
       'leader'
FROM organizations o
WHERE NOT EXISTS (
  SELECT 1 FROM invites i
  WHERE i.organization_id = o.id
    AND lower(i.permission) = 'leader'
);

-- Resolve duplicate invite codes (rare collision on backfill)
-- Re-run leader/member inserts manually if code collision occurs.

COMMIT;
