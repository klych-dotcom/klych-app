-- =============================================================================
-- KLYCH Rollback (destructive — use only in non-production or with backup)
-- Rolls back Organization Management additions only.
-- Does NOT drop core tables (organizations, users, invites, alerts).
-- =============================================================================

BEGIN;

-- Remove from realtime first
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS users;

-- Drop group tables (depends on users)
DROP TABLE IF EXISTS group_members CASCADE;
DROP TABLE IF EXISTS operational_groups CASCADE;

-- Remove org-management columns from users
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_department_id_fkey;
ALTER TABLE users DROP COLUMN IF EXISTS department_id;
ALTER TABLE users DROP COLUMN IF EXISTS status;
ALTER TABLE users DROP COLUMN IF EXISTS is_disabled;
ALTER TABLE users DROP COLUMN IF EXISTS last_activity_at;

-- Drop departments
DROP TABLE IF EXISTS departments CASCADE;

-- Revert invites to single-per-org (optional — may lose leader codes)
DROP INDEX IF EXISTS invites_org_permission_unique;
-- ALTER TABLE invites ADD CONSTRAINT invites_organization_id_key UNIQUE (organization_id);

-- Remove optional alerts.target
ALTER TABLE alerts DROP COLUMN IF EXISTS target;

COMMIT;

-- NOTE: Backfilled invite rows and role normalizations are NOT reversed.
-- Restore from Supabase backup for full rollback.
