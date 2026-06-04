-- KLYCH Organization Management MVP
-- Run manually in Supabase SQL editor. No RLS included in this phase.

-- ---------------------------------------------------------------------------
-- Departments
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  is_archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
);

CREATE INDEX IF NOT EXISTS departments_org_idx ON departments (organization_id);

-- ---------------------------------------------------------------------------
-- Users — org management columns
-- ---------------------------------------------------------------------------
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS department_id uuid REFERENCES departments(id);

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'available';

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_disabled boolean NOT NULL DEFAULT false;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS last_activity_at timestamptz DEFAULT now();

-- ---------------------------------------------------------------------------
-- Operational groups (temporary teams for future alert targeting)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS operational_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
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
