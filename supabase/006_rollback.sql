-- =============================================================================
-- KLYCH — 006 ROLLBACK: remove owner-only RLS for device_tokens
-- =============================================================================
-- Fully reverts migration 006. device_tokens returns to its prior (open) state.
-- No data is changed. Affects device_tokens only.
--
-- NOTE: dropping public.auth_user_id() is safe because (after these policy
-- drops) nothing else references it yet. If a later full-RLS migration has
-- already adopted auth_user_id(), KEEP the function — comment out its DROP.
-- =============================================================================

drop policy if exists device_tokens_select_own on public.device_tokens;
drop policy if exists device_tokens_insert_own on public.device_tokens;
drop policy if exists device_tokens_update_own on public.device_tokens;
drop policy if exists device_tokens_delete_own on public.device_tokens;

alter table public.device_tokens disable row level security;

drop function if exists public.auth_user_id();
