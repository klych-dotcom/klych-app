-- =============================================================================
-- KLYCH — 006 VERIFICATION: device_tokens owner-only RLS
-- =============================================================================
-- Non-destructive: runs in one transaction and ends with ROLLBACK (no rows
-- persist). Simulates two authenticated users (A, B) and service_role using
-- `set local role` + a forged request.jwt.claims sub, then asserts the policy
-- behavior. Run AFTER applying 006_device_tokens_rls.sql.
--
-- Run (psql):   psql "$DATABASE_URL" -f supabase/006_verification.sql
-- Also works pasted into the Supabase SQL Editor (runs as one transaction).
-- Pass: prints "DEVICE_TOKENS RLS OK". Any failed assert raises and aborts.
-- =============================================================================

begin;

-- ---- seed (privileged role); stash ids in session GUCs --------------------
do $$
declare
  v_org   uuid;
  v_a     uuid; v_aauth uuid;
  v_b     uuid; v_bauth uuid;
begin
  insert into organizations (name, owner_id)
    values ('VERIFY_DT_ORG', gen_random_uuid()) returning id into v_org;

  v_aauth := gen_random_uuid();
  v_bauth := gen_random_uuid();

  -- role 'leader' avoids the member-requires-department constraint
  insert into users (auth_id, organization_id, callsign, role, status)
    values (v_aauth, v_org, 'A', 'leader', 'available') returning id into v_a;
  insert into users (auth_id, organization_id, callsign, role, status)
    values (v_bauth, v_org, 'B', 'leader', 'available') returning id into v_b;

  insert into device_tokens (user_id, token, platform) values (v_a, 'verify_tokA', 'ios');
  insert into device_tokens (user_id, token, platform) values (v_b, 'verify_tokB', 'android');

  perform set_config('verify.a_id',   v_a::text,     false);
  perform set_config('verify.a_auth', v_aauth::text, false);
  perform set_config('verify.b_id',   v_b::text,     false);
  perform set_config('verify.b_auth', v_bauth::text, false);
end $$;

-- ---- act as authenticated user A ------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
                  json_build_object('sub', current_setting('verify.a_auth'))::text,
                  true);

do $$
declare c int;
begin
  -- SELECT: A sees only A's token
  select count(*) into c from device_tokens;
  if c <> 1 then raise exception 'A SELECT expected 1 got %', c; end if;
  if exists (select 1 from device_tokens where token = 'verify_tokB') then
    raise exception 'A can read B''s token (leak)';
  end if;

  -- INSERT own: allowed
  insert into device_tokens (user_id, token, platform)
    values (current_setting('verify.a_id')::uuid, 'verify_tokA2', 'ios');

  -- INSERT for B: denied by WITH CHECK (SQLSTATE 42501)
  begin
    insert into device_tokens (user_id, token, platform)
      values (current_setting('verify.b_id')::uuid, 'verify_tokB2', 'ios');
    raise exception 'A could INSERT a token for B (should be denied)';
  exception when insufficient_privilege then null;
  end;

  -- UPDATE other: 0 rows (B's row invisible to A)
  update device_tokens set is_active = false where token = 'verify_tokB';
  get diagnostics c = row_count;
  if c <> 0 then raise exception 'A UPDATE of B affected % rows', c; end if;

  -- UPDATE own: 1 row
  update device_tokens set is_active = false where token = 'verify_tokA';
  get diagnostics c = row_count;
  if c <> 1 then raise exception 'A UPDATE own affected % rows', c; end if;

  -- DELETE other: 0 rows
  delete from device_tokens where token = 'verify_tokB';
  get diagnostics c = row_count;
  if c <> 0 then raise exception 'A DELETE of B affected % rows', c; end if;

  -- DELETE own: 1 row
  delete from device_tokens where token = 'verify_tokA2';
  get diagnostics c = row_count;
  if c <> 1 then raise exception 'A DELETE own affected % rows', c; end if;
end $$;

reset role;

-- ---- act as authenticated user B (cannot see/alter A) ---------------------
set local role authenticated;
select set_config('request.jwt.claims',
                  json_build_object('sub', current_setting('verify.b_auth'))::text,
                  true);

do $$
declare c int;
begin
  -- B sees only its own remaining token (verify_tokB)
  select count(*) into c from device_tokens;
  if c <> 1 then raise exception 'B SELECT expected 1 got %', c; end if;
  if not exists (select 1 from device_tokens where token = 'verify_tokB') then
    raise exception 'B cannot see own token';
  end if;
end $$;

reset role;

-- ---- service_role retains full access (BYPASSRLS, no FORCE) ----------------
set local role service_role;
do $$
declare c int;
begin
  select count(*) into c from device_tokens;  -- sees all rows regardless of RLS
  if c < 1 then raise exception 'service_role blocked by RLS (saw % rows)', c; end if;
  -- service_role can write any user's token (dispatcher / admin tooling)
  update device_tokens set is_active = false where token = 'verify_tokB';
  get diagnostics c = row_count;
  if c <> 1 then raise exception 'service_role UPDATE affected % rows', c; end if;
end $$;
reset role;

-- ---- policy-set audit: exactly the 4 owner-only policies exist -------------
do $$
declare n int;
begin
  select count(*) into n from pg_policies
   where schemaname = 'public' and tablename = 'device_tokens';
  if n <> 4 then raise exception 'expected 4 device_tokens policies, found %', n; end if;

  if not exists (
    select 1 from pg_class c join pg_namespace nsp on nsp.oid = c.relnamespace
     where nsp.nspname = 'public' and c.relname = 'device_tokens' and c.relrowsecurity
  ) then
    raise exception 'RLS not enabled on device_tokens';
  end if;

  raise notice 'DEVICE_TOKENS RLS OK';
end $$;

rollback;
