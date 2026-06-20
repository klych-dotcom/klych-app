-- =============================================================================
-- KLYCH — 006: Owner-only RLS for device_tokens (SCOPED — this table only)
-- =============================================================================
-- Unlocks safe push-token registration. NO other table is touched. RLS is NOT
-- enabled on any other table by this migration.
--
-- Ownership model: device_tokens.user_id REFERENCES users.id; the caller is
-- identified by users.auth_id = auth.uid(). The auth_user_id() helper resolves
-- the caller's users.id (SECURITY DEFINER so the policy never recurses through
-- users' own RLS, and STABLE for per-statement caching).
--
-- service_role retains full access: RLS is enabled WITHOUT FORCE, and
-- service_role has BYPASSRLS — the future dispatcher reads tokens unaffected.
-- anon (pre-login) gets no policy => no access; token registration is
-- authenticated-only, which matches the app (tokens are written after login).
--
-- Idempotent: CREATE OR REPLACE function; DROP POLICY IF EXISTS before CREATE;
-- ENABLE ROW LEVEL SECURITY is a no-op if already enabled.
-- =============================================================================

-- Caller identity helper (resolves users.id for the current auth.uid()).
create or replace function public.auth_user_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from users where auth_id = auth.uid()
$$;

-- Enable RLS on device_tokens only.
alter table public.device_tokens enable row level security;

-- SELECT: a user can read only their own tokens.
drop policy if exists device_tokens_select_own on public.device_tokens;
create policy device_tokens_select_own
  on public.device_tokens
  for select
  to authenticated
  using (user_id = auth_user_id());

-- INSERT: a user can create tokens only for themselves.
drop policy if exists device_tokens_insert_own on public.device_tokens;
create policy device_tokens_insert_own
  on public.device_tokens
  for insert
  to authenticated
  with check (user_id = auth_user_id());

-- UPDATE: a user can update only their own tokens, and cannot reassign them.
drop policy if exists device_tokens_update_own on public.device_tokens;
create policy device_tokens_update_own
  on public.device_tokens
  for update
  to authenticated
  using (user_id = auth_user_id())
  with check (user_id = auth_user_id());

-- DELETE: a user can delete only their own tokens.
drop policy if exists device_tokens_delete_own on public.device_tokens;
create policy device_tokens_delete_own
  on public.device_tokens
  for delete
  to authenticated
  using (user_id = auth_user_id());
