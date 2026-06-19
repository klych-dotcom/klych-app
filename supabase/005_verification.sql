-- =============================================================================
-- KLYCH — 005 VERIFICATION: smoke tests for create_alert(...)
-- =============================================================================
-- Non-destructive: the whole script runs inside a single transaction and ends
-- with ROLLBACK, so it leaves no rows behind. Requires user_statuses to be
-- seeded (codes: available, on_duty, deployed, vacation, unavailable).
--
-- Run:  psql "$DATABASE_URL" -f supabase/005_verification.sql
-- Pass: prints "VERIFICATION OK". Any failed assert raises and aborts.
-- =============================================================================

begin;

do $$
declare
  v_org   uuid;
  v_dept1 uuid;
  v_dept2 uuid;
  v_grp   uuid;
  v_boss  uuid; -- dept1, available, sender
  v_cruzo uuid; -- dept1, deployed, group member
  v_folk  uuid; -- dept2, on_duty, group member
  v_off   uuid; -- dept2, deployed, DISABLED
  v_alert uuid;
  v_count integer;
  v_targets integer;
  v_receipts integer;
  v_raised boolean;
begin
  -- ---- seed -----------------------------------------------------------------
  insert into organizations (name, owner_id)
  values ('VERIFY_ORG', gen_random_uuid()) returning id into v_org;

  insert into departments (organization_id, name) values (v_org, 'HQ')
    returning id into v_dept1;
  insert into departments (organization_id, name) values (v_org, 'FIELD')
    returning id into v_dept2;

  insert into users (auth_id, organization_id, callsign, role, department_id, status, is_disabled)
    values (gen_random_uuid(), v_org, 'BOSS',  'leader', v_dept1, 'available', false)
    returning id into v_boss;
  insert into users (auth_id, organization_id, callsign, role, department_id, status, is_disabled)
    values (gen_random_uuid(), v_org, 'CRUZO', 'member', v_dept1, 'deployed',  false)
    returning id into v_cruzo;
  insert into users (auth_id, organization_id, callsign, role, department_id, status, is_disabled)
    values (gen_random_uuid(), v_org, 'FOLK',  'member', v_dept2, 'on_duty',   false)
    returning id into v_folk;
  insert into users (auth_id, organization_id, callsign, role, department_id, status, is_disabled)
    values (gen_random_uuid(), v_org, 'OFF',   'member', v_dept2, 'deployed',  true)
    returning id into v_off;

  insert into operational_groups (organization_id, name) values (v_org, 'CMD')
    returning id into v_grp;
  insert into group_members (group_id, user_id) values (v_grp, v_cruzo), (v_grp, v_folk);

  -- ---- case 1: org-wide excludes sender + disabled --------------------------
  select id, recipient_count into v_alert, v_count
  from public.create_alert(v_org, 'org wide', 'RED', v_boss, false, true);
  -- active users = BOSS, CRUZO, FOLK ; minus sender BOSS ; OFF disabled => 2
  if v_count <> 2 then raise exception 'CASE1 expected 2 got %', v_count; end if;
  select count(*) into v_receipts from alert_receipts where alert_id = v_alert;
  if v_receipts <> 2 then raise exception 'CASE1 receipts % <> 2', v_receipts; end if;
  select count(*) into v_targets from alert_targets
    where alert_id = v_alert and target_type = 'organization';
  if v_targets <> 1 then raise exception 'CASE1 org target % <> 1', v_targets; end if;

  -- ---- case 2: single department -------------------------------------------
  select id, recipient_count into v_alert, v_count
  from public.create_alert(v_org, 'dept', 'RED', v_boss, false, false,
                           '{}', array[v_dept1], '{}', '{}');
  -- dept1 = BOSS(sender excl), CRUZO => 1
  if v_count <> 1 then raise exception 'CASE2 expected 1 got %', v_count; end if;

  -- ---- case 3: single status ------------------------------------------------
  select id, recipient_count into v_alert, v_count
  from public.create_alert(v_org, 'status', 'RED', v_boss, false, false,
                           array['deployed'], '{}', '{}', '{}');
  -- deployed = CRUZO, OFF(disabled excl) => 1
  if v_count <> 1 then raise exception 'CASE3 expected 1 got %', v_count; end if;

  -- ---- case 4: single group -------------------------------------------------
  select id, recipient_count into v_alert, v_count
  from public.create_alert(v_org, 'group', 'RED', v_boss, false, false,
                           '{}', '{}', array[v_grp], '{}');
  -- group CMD = CRUZO, FOLK => 2
  if v_count <> 2 then raise exception 'CASE4 expected 2 got %', v_count; end if;

  -- ---- case 5: explicit users ----------------------------------------------
  select id, recipient_count into v_alert, v_count
  from public.create_alert(v_org, 'users', 'RED', v_boss, false, false,
                           '{}', '{}', '{}', array[v_folk]);
  if v_count <> 1 then raise exception 'CASE5 expected 1 got %', v_count; end if;
  select count(*) into v_targets from alert_target_users where alert_id = v_alert;
  if v_targets <> 1 then raise exception 'CASE5 target_users % <> 1', v_targets; end if;

  -- ---- case 6: multi-select UNION + dedup -----------------------------------
  select id, recipient_count into v_alert, v_count
  from public.create_alert(v_org, 'multi', 'RED', v_boss, false, false,
                           array['on_duty'], array[v_dept1], array[v_grp], '{}');
  -- on_duty{FOLK} U dept1{BOSS(excl),CRUZO} U group{CRUZO,FOLK} = {CRUZO,FOLK} => 2
  if v_count <> 2 then raise exception 'CASE6 expected 2 got %', v_count; end if;
  select count(*) into v_targets from alert_targets where alert_id = v_alert;
  if v_targets <> 3 then raise exception 'CASE6 targets % <> 3', v_targets; end if;

  -- ---- case 7: zero recipients raises and writes nothing --------------------
  v_raised := false;
  begin
    perform public.create_alert(v_org, 'none', 'RED', v_boss, false, false,
                                array['vacation'], '{}', '{}', '{}');
  exception when others then
    v_raised := true;
    if sqlerrm <> 'NO_RECIPIENTS' then
      raise exception 'CASE7 wrong error: %', sqlerrm;
    end if;
  end;
  if not v_raised then raise exception 'CASE7 expected NO_RECIPIENTS'; end if;
  -- no alert row should exist for message 'none'
  if exists (select 1 from alerts where organization_id = v_org and message = 'none') then
    raise exception 'CASE7 orphan alert row created';
  end if;

  -- ---- case 8: invalid level raises ----------------------------------------
  v_raised := false;
  begin
    perform public.create_alert(v_org, 'bad', 'PURPLE', v_boss, false, true);
  exception when others then
    v_raised := true;
  end;
  if not v_raised then raise exception 'CASE8 expected INVALID_LEVEL'; end if;

  raise notice 'VERIFICATION OK';
end;
$$;

rollback;
