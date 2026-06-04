-- =============================================================================
-- KLYCH v2 — Schema Integrity Verification
-- Run after schema.sql + seed.sql
-- =============================================================================

-- 1. All core tables exist
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'user_statuses', 'department_templates',
    'organizations', 'departments', 'users',
    'invites', 'invite_redemptions',
    'operational_groups', 'group_members',
    'alerts', 'alert_targets', 'alert_target_users', 'alert_receipts',
    'alert_templates', 'audit_log', 'device_tokens'
  )
ORDER BY table_name;
-- Expected: 16 rows

-- 2. Status catalog seeded
SELECT code, label FROM user_statuses ORDER BY sort_order;
-- Expected: 5 rows

-- 3. Department templates seeded
SELECT code, name FROM department_templates ORDER BY sort_order;
-- Expected: 5 rows

-- 4. Role constraint on users
SELECT conname FROM pg_constraint
WHERE conrelid = 'users'::regclass AND conname LIKE '%role%';

-- 5. Invite role constraint (member | leader only)
SELECT conname FROM pg_constraint
WHERE conrelid = 'invites'::regclass;

-- 6. Alert level constraint
SELECT conname FROM pg_constraint
WHERE conrelid = 'alerts'::regclass AND contype = 'c';

-- 7. Foreign keys from users to departments and statuses
SELECT
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.table_name = 'users'
  AND tc.constraint_type = 'FOREIGN KEY';

-- 8. RLS not enabled yet (v2 bootstrap — policies come later)
SELECT relname, relrowsecurity
FROM pg_class
WHERE relname IN (
  'organizations', 'users', 'departments', 'invites', 'alerts',
  'alert_receipts', 'operational_groups', 'group_members', 'audit_log'
)
ORDER BY relname;
-- Expected: relrowsecurity = false until RLS migration

-- 9. Realtime publication
SELECT tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('users', 'alerts', 'alert_receipts')
ORDER BY tablename;
-- Expected: 3 rows

-- 10. Helper function exists
SELECT proname FROM pg_proc WHERE proname = 'seed_org_departments';

-- 11. Cross-org integrity triggers
SELECT tgname, tgrelid::regclass AS table_name
FROM pg_trigger
WHERE tgname IN (
  'group_members_same_org',
  'users_department_same_org',
  'alert_targets_same_org',
  'alert_target_users_same_org',
  'alert_templates_same_org'
)
ORDER BY tgname;
-- Expected: 5 rows

-- 12. Alert templates table
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'alert_templates'
ORDER BY ordinal_position;

-- ---------------------------------------------------------------------------
-- Post-registration smoke (replace UUID after creating test org in app)
-- ---------------------------------------------------------------------------
-- SELECT d.name FROM departments d WHERE d.organization_id = '<org-id>' AND NOT d.is_archived;
-- SELECT role, code, expires_at > now() AS valid FROM invites WHERE organization_id = '<org-id>';
