-- Optional additive migration for KLYCH milestone (run manually in Supabase SQL editor).
-- Enables alert targeting without redesigning existing tables.

ALTER TABLE alerts
  ADD COLUMN IF NOT EXISTS target text DEFAULT 'organization';

-- Allow multiple invite codes per organization (member + leader).
-- If you have a UNIQUE constraint on invites(organization_id) alone, drop it first:
-- ALTER TABLE invites DROP CONSTRAINT IF EXISTS invites_organization_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS invites_org_permission_unique
  ON invites (organization_id, permission);
