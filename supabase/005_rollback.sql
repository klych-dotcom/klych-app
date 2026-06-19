-- =============================================================================
-- KLYCH — 005 ROLLBACK: drop atomic alert creation RPC
-- =============================================================================
-- Order of operations when rolling back in production:
--   1. Re-release the previous app build (legacy multi-step createAlert) FIRST.
--   2. Then run this file.
-- The function is additive and tables are unchanged, so dropping it only affects
-- app versions that call supabase.rpc('create_alert', ...). No data loss.
-- =============================================================================

drop function if exists public.create_alert(
  uuid, text, text, uuid, boolean, boolean, text[], uuid[], uuid[], uuid[]
);
