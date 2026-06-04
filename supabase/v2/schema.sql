-- =============================================================================
-- KLYCH v2 — Clean Production Schema
-- Rebuild from scratch. No RLS policies (enable RLS separately).
-- Compatible with current Flutter + full product vision.
-- =============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- ENUM-like reference: user statuses (seeded in seed.sql)
-- ---------------------------------------------------------------------------
CREATE TABLE user_statuses (
  code        text PRIMARY KEY,
  label       text NOT NULL,
  description text,
  sort_order  smallint NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- Global department name templates (copied into org on creation)
-- ---------------------------------------------------------------------------
CREATE TABLE department_templates (
  code        text PRIMARY KEY,
  name        text NOT NULL UNIQUE,
  sort_order  smallint NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- Organizations
-- ---------------------------------------------------------------------------
CREATE TABLE organizations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  owner_id    uuid NOT NULL,  -- auth.users.id of founding admin
  settings    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX organizations_owner_id_idx ON organizations (owner_id);

-- ---------------------------------------------------------------------------
-- Departments (admin-managed, per organization)
-- ---------------------------------------------------------------------------
CREATE TABLE departments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name             text NOT NULL,
  is_archived      boolean NOT NULL DEFAULT false,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT departments_org_name_unique UNIQUE (organization_id, name)
);

CREATE INDEX departments_org_idx ON departments (organization_id);
CREATE INDEX departments_org_active_idx ON departments (organization_id)
  WHERE is_archived = false;

-- ---------------------------------------------------------------------------
-- Users (profile linked to Supabase Auth)
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id          uuid NOT NULL UNIQUE,  -- auth.users.id
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  callsign         text NOT NULL,
  display_name     text,
  role             text NOT NULL CHECK (role IN ('admin', 'leader', 'member')),
  department_id    uuid REFERENCES departments(id) ON DELETE SET NULL,
  status           text NOT NULL DEFAULT 'available' REFERENCES user_statuses(code),
  is_disabled      boolean NOT NULL DEFAULT false,
  last_activity_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_member_requires_department CHECK (
    role <> 'member' OR department_id IS NOT NULL
  )
);

CREATE INDEX users_organization_id_idx ON users (organization_id);
CREATE INDEX users_org_role_idx ON users (organization_id, role);
CREATE INDEX users_org_status_idx ON users (organization_id, status)
  WHERE is_disabled = false;
CREATE INDEX users_org_dept_idx ON users (organization_id, department_id)
  WHERE department_id IS NOT NULL AND is_disabled = false;

-- ---------------------------------------------------------------------------
-- Invites (admin-generated; role locked at redemption)
-- ---------------------------------------------------------------------------
CREATE TABLE invites (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  code             text NOT NULL UNIQUE,
  role             text NOT NULL CHECK (role IN ('member', 'leader')),
  max_uses         integer NOT NULL DEFAULT 1 CHECK (max_uses > 0),
  use_count        integer NOT NULL DEFAULT 0 CHECK (use_count >= 0),
  expires_at       timestamptz NOT NULL,
  revoked_at       timestamptz,
  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT invites_use_count_lte_max CHECK (use_count <= max_uses)
);

CREATE INDEX invites_organization_id_idx ON invites (organization_id);
CREATE INDEX invites_org_role_idx ON invites (organization_id, role);
CREATE INDEX invites_active_idx ON invites (organization_id, role)
  WHERE revoked_at IS NULL AND use_count < max_uses;

CREATE TABLE invite_redemptions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_id   uuid NOT NULL REFERENCES invites(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT invite_redemptions_unique UNIQUE (invite_id, user_id)
);

CREATE INDEX invite_redemptions_user_idx ON invite_redemptions (user_id);

-- ---------------------------------------------------------------------------
-- Operational groups (leader-managed)
-- ---------------------------------------------------------------------------
CREATE TABLE operational_groups (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name             text NOT NULL,
  created_by       uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT operational_groups_org_name_unique UNIQUE (organization_id, name)
);

CREATE INDEX operational_groups_org_idx ON operational_groups (organization_id);
CREATE INDEX operational_groups_created_by_idx ON operational_groups (created_by);

CREATE TABLE group_members (
  group_id   uuid NOT NULL REFERENCES operational_groups(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  added_by   uuid REFERENCES users(id) ON DELETE SET NULL,
  added_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE INDEX group_members_user_idx ON group_members (user_id);

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
CREATE TABLE alerts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  level            text NOT NULL CHECK (level IN ('RED', 'GREEN')),
  message          text NOT NULL,
  is_test          boolean NOT NULL DEFAULT false,
  sender_user_id   uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX alerts_organization_id_idx ON alerts (organization_id);
CREATE INDEX alerts_org_created_idx ON alerts (organization_id, created_at DESC);
CREATE INDEX alerts_sender_idx ON alerts (sender_user_id);

-- Targeting: one or more target rows per alert (union semantics at delivery time)
CREATE TABLE alert_targets (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id         uuid NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
  target_type      text NOT NULL CHECK (
    target_type IN ('organization', 'department', 'group', 'users', 'status')
  ),
  department_id    uuid REFERENCES departments(id) ON DELETE CASCADE,
  group_id         uuid REFERENCES operational_groups(id) ON DELETE CASCADE,
  status_code      text REFERENCES user_statuses(code) ON DELETE CASCADE,
  CONSTRAINT alert_targets_ref_check CHECK (
    (target_type = 'organization' AND department_id IS NULL AND group_id IS NULL AND status_code IS NULL)
    OR (target_type = 'department' AND department_id IS NOT NULL AND group_id IS NULL AND status_code IS NULL)
    OR (target_type = 'group' AND group_id IS NOT NULL AND department_id IS NULL AND status_code IS NULL)
    OR (target_type = 'status' AND status_code IS NOT NULL AND department_id IS NULL AND group_id IS NULL)
    OR (target_type = 'users' AND department_id IS NULL AND group_id IS NULL AND status_code IS NULL)
  )
);

CREATE INDEX alert_targets_alert_idx ON alert_targets (alert_id);
CREATE INDEX alert_targets_department_idx ON alert_targets (department_id)
  WHERE department_id IS NOT NULL;
CREATE INDEX alert_targets_group_idx ON alert_targets (group_id)
  WHERE group_id IS NOT NULL;
CREATE INDEX alert_targets_status_idx ON alert_targets (status_code)
  WHERE status_code IS NOT NULL;

-- Explicit user list when target_type = 'users'
CREATE TABLE alert_target_users (
  alert_id   uuid NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (alert_id, user_id)
);

CREATE INDEX alert_target_users_user_idx ON alert_target_users (user_id);

-- ---------------------------------------------------------------------------
-- Alert acknowledgements / delivery tracking
-- ---------------------------------------------------------------------------
CREATE TABLE alert_receipts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id        uuid NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  delivered_at    timestamptz,
  opened_at       timestamptz,
  acknowledged_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT alert_receipts_unique UNIQUE (alert_id, user_id)
);

CREATE INDEX alert_receipts_alert_idx ON alert_receipts (alert_id);
CREATE INDEX alert_receipts_user_idx ON alert_receipts (user_id);
CREATE INDEX alert_receipts_unacked_idx ON alert_receipts (alert_id)
  WHERE acknowledged_at IS NULL;
CREATE INDEX alert_receipts_user_created_idx ON alert_receipts (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Alert templates (org-specific reusable messages; optional default targeting)
-- ---------------------------------------------------------------------------
CREATE TABLE alert_templates (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name                 text NOT NULL,
  level                text NOT NULL CHECK (level IN ('RED', 'GREEN')),
  message              text NOT NULL,
  default_target_type  text CHECK (
    default_target_type IS NULL OR default_target_type IN (
      'organization', 'department', 'group', 'users', 'status'
    )
  ),
  default_department_id uuid REFERENCES departments(id) ON DELETE SET NULL,
  default_group_id      uuid REFERENCES operational_groups(id) ON DELETE SET NULL,
  default_status_code   text REFERENCES user_statuses(code) ON DELETE SET NULL,
  is_archived          boolean NOT NULL DEFAULT false,
  created_by           uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT alert_templates_org_name_unique UNIQUE (organization_id, name)
);

CREATE INDEX alert_templates_org_idx ON alert_templates (organization_id);
CREATE INDEX alert_templates_org_active_idx ON alert_templates (organization_id)
  WHERE is_archived = false;

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------
CREATE TABLE audit_log (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  actor_user_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  action           text NOT NULL,
  entity_type      text NOT NULL,
  entity_id        uuid,
  metadata         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_log_org_created_idx ON audit_log (organization_id, created_at DESC);
CREATE INDEX audit_log_entity_idx ON audit_log (entity_type, entity_id);

-- ---------------------------------------------------------------------------
-- FCM preparation (not used by Flutter yet)
-- ---------------------------------------------------------------------------
CREATE TABLE device_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token       text NOT NULL,
  platform    text NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
  is_active   boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT device_tokens_token_unique UNIQUE (token),
  CONSTRAINT device_tokens_user_token_unique UNIQUE (user_id, token)
);

CREATE INDEX device_tokens_user_idx ON device_tokens (user_id);
CREATE INDEX device_tokens_active_idx ON device_tokens (user_id)
  WHERE is_active = true;

-- ---------------------------------------------------------------------------
-- updated_at trigger helper
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER organizations_updated_at
  BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER departments_updated_at
  BEFORE UPDATE ON departments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER operational_groups_updated_at
  BEFORE UPDATE ON operational_groups
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER alert_templates_updated_at
  BEFORE UPDATE ON alert_templates
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Realtime publication (Supabase)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'users'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE users;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'alerts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE alerts;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'alert_receipts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE alert_receipts;
  END IF;
EXCEPTION
  WHEN undefined_object THEN
    RAISE NOTICE 'Create supabase_realtime publication via Supabase Dashboard first';
END $$;

-- ---------------------------------------------------------------------------
-- RLS preparation (DO NOT enable until policies migration is applied)
-- Enabling RLS without policies blocks all client access.
-- Future migration: ALTER TABLE ... ENABLE ROW LEVEL SECURITY + CREATE POLICY ...
-- ---------------------------------------------------------------------------
-- Tables scoped by organization_id for future policies:
--   organizations, departments, users, invites, invite_redemptions,
--   operational_groups, group_members, alerts, alert_targets,
--   alert_target_users, alert_receipts, alert_templates, audit_log, device_tokens
--
-- Child tables without organization_id use EXISTS subqueries via parent:
--   alert_targets      → alerts.organization_id
--   alert_target_users → alerts.organization_id
--   group_members      → operational_groups.organization_id OR users.organization_id
--   invite_redemptions → invites.organization_id
--   device_tokens      → users.organization_id

-- ---------------------------------------------------------------------------
-- Cross-organization integrity (security readiness before RLS)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION assert_group_member_same_org()
RETURNS trigger AS $$
DECLARE
  group_org uuid;
  user_org  uuid;
BEGIN
  SELECT organization_id INTO group_org
  FROM operational_groups WHERE id = NEW.group_id;

  SELECT organization_id INTO user_org
  FROM users WHERE id = NEW.user_id;

  IF group_org IS DISTINCT FROM user_org THEN
    RAISE EXCEPTION 'group_members: user and group must belong to the same organization';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER group_members_same_org
  BEFORE INSERT OR UPDATE ON group_members
  FOR EACH ROW EXECUTE FUNCTION assert_group_member_same_org();

CREATE OR REPLACE FUNCTION assert_user_department_same_org()
RETURNS trigger AS $$
DECLARE
  dept_org uuid;
BEGIN
  IF NEW.department_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT organization_id INTO dept_org FROM departments WHERE id = NEW.department_id;

  IF dept_org IS DISTINCT FROM NEW.organization_id THEN
    RAISE EXCEPTION 'users: department must belong to user organization';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_department_same_org
  BEFORE INSERT OR UPDATE OF department_id, organization_id ON users
  FOR EACH ROW EXECUTE FUNCTION assert_user_department_same_org();

CREATE OR REPLACE FUNCTION assert_alert_target_same_org()
RETURNS trigger AS $$
DECLARE
  alert_org uuid;
  ref_org   uuid;
BEGIN
  SELECT organization_id INTO alert_org FROM alerts WHERE id = NEW.alert_id;

  IF NEW.department_id IS NOT NULL THEN
    SELECT organization_id INTO ref_org FROM departments WHERE id = NEW.department_id;
    IF ref_org IS DISTINCT FROM alert_org THEN
      RAISE EXCEPTION 'alert_targets: department must belong to alert organization';
    END IF;
  END IF;

  IF NEW.group_id IS NOT NULL THEN
    SELECT organization_id INTO ref_org FROM operational_groups WHERE id = NEW.group_id;
    IF ref_org IS DISTINCT FROM alert_org THEN
      RAISE EXCEPTION 'alert_targets: group must belong to alert organization';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER alert_targets_same_org
  BEFORE INSERT OR UPDATE ON alert_targets
  FOR EACH ROW EXECUTE FUNCTION assert_alert_target_same_org();

CREATE OR REPLACE FUNCTION assert_alert_target_user_same_org()
RETURNS trigger AS $$
DECLARE
  alert_org uuid;
  user_org  uuid;
BEGIN
  SELECT organization_id INTO alert_org FROM alerts WHERE id = NEW.alert_id;
  SELECT organization_id INTO user_org FROM users WHERE id = NEW.user_id;

  IF alert_org IS DISTINCT FROM user_org THEN
    RAISE EXCEPTION 'alert_target_users: user must belong to alert organization';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER alert_target_users_same_org
  BEFORE INSERT OR UPDATE ON alert_target_users
  FOR EACH ROW EXECUTE FUNCTION assert_alert_target_user_same_org();

CREATE OR REPLACE FUNCTION assert_alert_template_refs_same_org()
RETURNS trigger AS $$
DECLARE
  ref_org uuid;
BEGIN
  IF NEW.default_department_id IS NOT NULL THEN
    SELECT organization_id INTO ref_org FROM departments WHERE id = NEW.default_department_id;
    IF ref_org IS DISTINCT FROM NEW.organization_id THEN
      RAISE EXCEPTION 'alert_templates: default department must belong to template organization';
    END IF;
  END IF;

  IF NEW.default_group_id IS NOT NULL THEN
    SELECT organization_id INTO ref_org FROM operational_groups WHERE id = NEW.default_group_id;
    IF ref_org IS DISTINCT FROM NEW.organization_id THEN
      RAISE EXCEPTION 'alert_templates: default group must belong to template organization';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER alert_templates_same_org
  BEFORE INSERT OR UPDATE ON alert_templates
  FOR EACH ROW EXECUTE FUNCTION assert_alert_template_refs_same_org();

-- ---------------------------------------------------------------------------
-- Helper: seed departments for a new organization from templates
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION seed_org_departments(p_org_id uuid)
RETURNS void AS $$
BEGIN
  INSERT INTO departments (organization_id, name)
  SELECT p_org_id, dt.name
  FROM department_templates dt
  ORDER BY dt.sort_order
  ON CONFLICT (organization_id, name) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE alert_targets IS
  'Delivery resolution: union of all targets on an alert. Implemented server-side in a future Edge Function.';
COMMENT ON TABLE alert_receipts IS
  'Per-user delivery and acknowledgement state. FCM/webhook can set delivered_at; app sets opened_at/acknowledged_at.';
COMMENT ON TABLE alert_templates IS
  'Org-specific reusable alert presets. Does not send alerts; referenced when composing new alerts.';
COMMENT ON TABLE device_tokens IS
  'FCM registration per device. token is globally unique; deactivate via is_active instead of delete.';
COMMENT ON COLUMN invites.role IS
  'Locked role assigned on redemption. Users cannot self-select leader.';
COMMENT ON COLUMN users.status IS
  'Operational availability set by user. Not device presence — use last_activity_at for connectivity heuristics.';
COMMENT ON COLUMN users.role IS
  'Authorization only: admin, leader, member. Not rank or department function.';
