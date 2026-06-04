-- =============================================================================
-- KLYCH Post-Migration Verification
-- All checks should return expected results documented inline.
-- =============================================================================

-- 1. Required tables exist
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'organizations', 'users', 'departments', 'invites',
    'alerts', 'operational_groups', 'group_members'
  )
ORDER BY table_name;
-- Expected: 7 rows

-- 2. Required users columns
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
  AND column_name IN (
    'id', 'auth_id', 'organization_id', 'callsign', 'role', 'permission',
    'department_id', 'status', 'is_disabled', 'last_activity_at', 'created_at'
  )
ORDER BY column_name;
-- Expected: 11 rows; status/is_disabled NOT NULL

-- 3. Organizations with zero departments (should be empty)
SELECT o.id, o.name
FROM organizations o
LEFT JOIN departments d ON d.organization_id = o.id AND d.is_archived = false
GROUP BY o.id, o.name
HAVING count(d.id) = 0;

-- 4. Users missing department (should be empty after backfill)
SELECT id, callsign, organization_id
FROM users
WHERE department_id IS NULL;

-- 5. Organizations missing member or leader invite
SELECT o.name,
       bool_or(lower(coalesce(i.permission, 'member')) = 'leader') AS has_leader,
       bool_or(lower(coalesce(i.permission, 'member')) NOT IN ('leader', 'admin')) AS has_member
FROM organizations o
LEFT JOIN invites i ON i.organization_id = o.id
GROUP BY o.id, o.name
HAVING NOT bool_or(lower(coalesce(i.permission, 'member')) = 'leader')
    OR NOT bool_or(lower(coalesce(i.permission, 'member')) NOT IN ('leader', 'admin'));

-- 6. Invite code uniqueness
SELECT code, count(*) AS cnt
FROM invites
GROUP BY code
HAVING count(*) > 1;
-- Expected: 0 rows

-- 7. Foreign keys on users.department_id
SELECT conname, confrelid::regclass AS references_table
FROM pg_constraint
WHERE conrelid = 'users'::regclass
  AND contype = 'f'
  AND conname = 'users_department_id_fkey';

-- 8. Realtime publication
SELECT tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('alerts', 'users');
-- Expected: alerts, users

-- 9. Sample department load (replace UUID)
-- SELECT id, name FROM departments
-- WHERE organization_id = '<your-org-id>' AND is_archived = false
-- ORDER BY name;
