-- =============================================================================
-- KLYCH Production Sync Migration
-- Synchronizes Supabase schema with current Flutter codebase (2025-05).
-- Run in Supabase SQL Editor. No RLS. Idempotent where possible.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. ORGANIZATIONS (baseline — create only if missing)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  owner_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2. DEPARTMENTS (required by invite registration + org management)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  is_archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT departments_org_name_unique UNIQUE (organization_id, name)
);

CREATE INDEX IF NOT EXISTS departments_org_idx
  ON departments (organization_id);

CREATE INDEX IF NOT EXISTS departments_org_active_idx
  ON departments (organization_id)
  WHERE is_archived = false;

-- ---------------------------------------------------------------------------
-- 3. USERS (baseline + org-management columns)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id uuid NOT NULL,
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  callsign text,
  name text,
  role text,
  permission text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS department_id uuid;
ALTER TABLE users ADD COLUMN IF NOT EXISTS status text DEFAULT 'available';
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_disabled boolean DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_activity_at timestamptz DEFAULT now();

-- Backfill NULLs before NOT NULL constraints
UPDATE users SET status = 'available' WHERE status IS NULL;
UPDATE users SET is_disabled = false WHERE is_disabled IS NULL;
UPDATE users SET last_activity_at = COALESCE(last_activity_at, created_at, now())
  WHERE last_activity_at IS NULL;

ALTER TABLE users ALTER COLUMN status SET DEFAULT 'available';
ALTER TABLE users ALTER COLUMN status SET NOT NULL;
ALTER TABLE users ALTER COLUMN is_disabled SET DEFAULT false;
ALTER TABLE users ALTER COLUMN is_disabled SET NOT NULL;

-- FK (safe re-run)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_department_id_fkey'
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT users_department_id_fkey
      FOREIGN KEY (department_id) REFERENCES departments(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS users_auth_id_unique ON users (auth_id);
CREATE INDEX IF NOT EXISTS users_organization_id_idx ON users (organization_id);
CREATE INDEX IF NOT EXISTS users_org_status_idx ON users (organization_id, status)
  WHERE is_disabled = false;

-- ---------------------------------------------------------------------------
-- 4. INVITES (member + leader codes per org)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  code text NOT NULL,
  permission text NOT NULL DEFAULT 'member',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Drop legacy single-invite-per-org constraint if present
ALTER TABLE invites DROP CONSTRAINT IF EXISTS invites_organization_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS invites_code_unique ON invites (code);
CREATE UNIQUE INDEX IF NOT EXISTS invites_org_permission_unique
  ON invites (organization_id, permission);
CREATE INDEX IF NOT EXISTS invites_organization_id_idx ON invites (organization_id);

-- ---------------------------------------------------------------------------
-- 5. ALERTS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  message text NOT NULL,
  type text NOT NULL DEFAULT 'RED',
  created_by uuid,
  created_by_name text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Optional column for future targeting (Flutter does not insert yet)
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS target text DEFAULT 'organization';

CREATE INDEX IF NOT EXISTS alerts_organization_id_idx ON alerts (organization_id);
CREATE INDEX IF NOT EXISTS alerts_org_created_idx ON alerts (organization_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 6. OPERATIONAL GROUPS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS operational_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT operational_groups_org_name_unique UNIQUE (organization_id, name)
);

CREATE INDEX IF NOT EXISTS operational_groups_org_idx
  ON operational_groups (organization_id);

CREATE TABLE IF NOT EXISTS group_members (
  group_id uuid NOT NULL REFERENCES operational_groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  added_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS group_members_user_idx ON group_members (user_id);

-- ---------------------------------------------------------------------------
-- 7. REALTIME (required for alert + status subscriptions)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE alerts;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'users'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE users;
  END IF;
EXCEPTION
  WHEN undefined_object THEN
    RAISE NOTICE 'supabase_realtime publication not found — enable Realtime in Supabase dashboard';
END $$;

COMMIT;
