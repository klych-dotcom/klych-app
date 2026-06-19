-- =============================================================================
-- KLYCH — 005: Atomic alert creation RPC
-- =============================================================================
-- Replaces the client-side multi-step alert creation (alerts -> alert_targets ->
-- alert_target_users -> alert_receipts) with a single transactional function.
--
-- Behavior-preserving:
--   * alert_targets rows written identically to the legacy client output
--   * recipient resolution mirrors AlertDeliveryService.resolveFromTargetRows /
--     RecipientResolver (UNION across categories, active users only, sender
--     excluded, duplicates removed)
--   * zero recipients -> RAISE EXCEPTION 'NO_RECIPIENTS' -> full rollback
--     (preserves Dart NoRecipientsException)
--
-- Additive only: no table / column / constraint / index / trigger / RLS change.
-- Idempotent: CREATE OR REPLACE.
-- =============================================================================

create or replace function public.create_alert(
  p_organization_id uuid,
  p_message         text,
  p_level           text,
  p_sender_user_id  uuid,
  p_is_test         boolean default false,
  p_org_wide        boolean default false,
  p_status_codes    text[]  default '{}',
  p_department_ids  uuid[]  default '{}',
  p_group_ids       uuid[]  default '{}',
  p_user_ids        uuid[]  default '{}'
)
returns table (
  id              uuid,
  organization_id uuid,
  message         text,
  level           text,
  is_test         boolean,
  sender_user_id  uuid,
  created_at      timestamptz,
  recipient_count integer
)
language plpgsql
volatile
security invoker
set search_path = public
as $$
declare
  v_alert alerts%rowtype;
  v_count integer;
begin
  -- ---- validation (matches current client guards) ---------------------------
  if p_level not in ('RED', 'GREEN') then
    raise exception 'INVALID_LEVEL' using errcode = 'P0001';
  end if;

  if coalesce(btrim(p_message), '') = '' then
    raise exception 'EMPTY_MESSAGE' using errcode = 'P0001';
  end if;

  -- ---- 1) alert -------------------------------------------------------------
  insert into alerts (organization_id, message, level, sender_user_id, is_test)
  values (p_organization_id, p_message, p_level, p_sender_user_id, p_is_test)
  returning * into v_alert;

  -- ---- 2/3) targets + explicit users ---------------------------------------
  if p_org_wide then
    insert into alert_targets (alert_id, target_type)
    values (v_alert.id, 'organization');
  else
    insert into alert_targets (alert_id, target_type, status_code)
      select v_alert.id, 'status', c from unnest(p_status_codes) as c;

    insert into alert_targets (alert_id, target_type, department_id)
      select v_alert.id, 'department', d from unnest(p_department_ids) as d;

    insert into alert_targets (alert_id, target_type, group_id)
      select v_alert.id, 'group', g from unnest(p_group_ids) as g;

    if coalesce(array_length(p_user_ids, 1), 0) > 0 then
      insert into alert_targets (alert_id, target_type)
      values (v_alert.id, 'users');

      insert into alert_target_users (alert_id, user_id)
        select v_alert.id, u from unnest(p_user_ids) as u
        on conflict do nothing;
    end if;
  end if;

  -- ---- 4/5/6/7) resolve recipients (UNION, active, <> sender, distinct) -----
  with recip as (
    select u.id
    from users u
    where u.organization_id = p_organization_id
      and u.is_disabled = false
      and u.id <> p_sender_user_id
      and (
        p_org_wide
        or u.status = any(p_status_codes)
        or u.department_id = any(p_department_ids)
        or u.id = any(p_user_ids)
        or exists (
          select 1
          from group_members gm
          where gm.user_id = u.id
            and gm.group_id = any(p_group_ids)
        )
      )
  )
  insert into alert_receipts (alert_id, user_id)
  select v_alert.id, r.id from recip r
  on conflict (alert_id, user_id) do nothing;

  get diagnostics v_count = row_count;

  -- ---- 10) block + rollback when no recipients (== NoRecipientsException) ---
  if v_count = 0 then
    raise exception 'NO_RECIPIENTS' using errcode = 'P0001';
  end if;

  -- ---- 9) return ------------------------------------------------------------
  return query
    select v_alert.id,
           v_alert.organization_id,
           v_alert.message,
           v_alert.level,
           v_alert.is_test,
           v_alert.sender_user_id,
           v_alert.created_at,
           v_count;
end;
$$;

grant execute on function public.create_alert(
  uuid, text, text, uuid, boolean, boolean, text[], uuid[], uuid[], uuid[]
) to anon, authenticated;
