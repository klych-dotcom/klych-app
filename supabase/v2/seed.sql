-- =============================================================================
-- KLYCH v2 — Reference Seed Data
-- Run after schema.sql on a fresh database.
-- Does NOT create demo organizations (app creates those via registration).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- User statuses (required FK for users.status)
-- ---------------------------------------------------------------------------
INSERT INTO user_statuses (code, label, description, sort_order) VALUES
  ('available',   'Available',   'Present and available',              1),
  ('on_duty',     'On Duty',     'Currently on shift',               2),
  ('deployed',    'Deployed',    'On mission or travel',             3),
  ('vacation',    'Vacation',    'Unavailable — vacation',           4),
  ('unavailable', 'Unavailable', 'Temporarily unavailable',          5)
ON CONFLICT (code) DO UPDATE SET
  label       = EXCLUDED.label,
  description = EXCLUDED.description,
  sort_order  = EXCLUDED.sort_order;

-- Note: "offline" is intentionally NOT a user_status.
-- Status = operational availability (user-declared, used for alert targeting).
-- Device presence/connectivity is inferred from last_activity_at or a future presence layer.

-- ---------------------------------------------------------------------------
-- Default department templates (copied per org via seed_org_departments())
-- ---------------------------------------------------------------------------
INSERT INTO department_templates (code, name, sort_order) VALUES
  ('headquarters',   'Headquarters',   1),
  ('medics',         'Medics',         2),
  ('drivers',        'Drivers',        3),
  ('logistics',      'Logistics',      4),
  ('communications', 'Communications', 5)
ON CONFLICT (code) DO UPDATE SET
  name       = EXCLUDED.name,
  sort_order = EXCLUDED.sort_order;

-- ---------------------------------------------------------------------------
-- Alert templates are org-specific (created by admin/leader after registration).
-- Example rows to insert per organization (replace :org_id and :user_id):
--
-- INSERT INTO alert_templates (organization_id, name, level, message, created_by) VALUES
--   (:org_id, 'RED ALERT',       'RED',   'Immediate action required.', :user_id),
--   (:org_id, 'GREEN ALERT',     'GREEN', 'All clear.',                 :user_id),
--   (:org_id, 'Evacuation',      'RED',   'Evacuate to rally point.',   :user_id),
--   (:org_id, 'Medical response','RED',   'Medical team respond.',      :user_id),
--   (:org_id, 'Comms check',     'GREEN', 'Confirm radio contact.',     :user_id);
