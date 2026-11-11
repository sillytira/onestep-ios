\set ON_ERROR_STOP on
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth,public to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;
\ir 001_points_foundation.sql

insert into auth.users values ('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
insert into public.onestep_admins values ('11111111-1111-4111-8111-111111111111');

set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $$ begin
  begin
    perform public.onestep_admin_adjust_points('22222222-2222-4222-8222-222222222222',500,'Forged award','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    raise exception 'Non-admin award unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.onestep_admins values ('22222222-2222-4222-8222-222222222222');
    raise exception 'Client self-promotion unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;
insert into public.onestep_profiles(user_id,display_name) values ('22222222-2222-4222-8222-222222222222','Beta friend');

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
insert into public.onestep_profiles(user_id,display_name) values ('11111111-1111-4111-8111-111111111111','Beta owner');
do $$ declare balance bigint; begin
  balance := public.onestep_admin_adjust_points('11111111-1111-4111-8111-111111111111',5,'Test task award','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  if balance <> 5 then raise exception 'Incorrect first balance'; end if;
  balance := public.onestep_admin_adjust_points('11111111-1111-4111-8111-111111111111',5,'Test task award','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  if balance <> 5 then raise exception 'Duplicate event credited twice'; end if;
  begin
    perform public.onestep_admin_adjust_points('11111111-1111-4111-8111-111111111111',-6,'Test overdraft','cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    raise exception 'Overdraft unexpectedly succeeded' using errcode = 'P0002';
  exception when raise_exception then null; end;
  if (select count(*) from public.onestep_leaderboard) <> 0 then raise exception 'Opted-out profile leaked'; end if;
end $$;
update public.onestep_profiles set leaderboard_opt_in=true where user_id=auth.uid();

select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $$ begin
  if (select count(*) from public.onestep_points_ledger) <> 0 then raise exception 'Private ledger leaked'; end if;
  if (select count(*) from public.onestep_profiles) <> 1 then raise exception 'Private profiles leaked'; end if;
  if (select points from public.onestep_leaderboard where display_name='Beta owner') is distinct from 5 then raise exception 'Opt-in ranking unavailable'; end if;
  begin
    insert into public.onestep_points_ledger(event_id,user_id,delta,reason,actor_id) values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd',auth.uid(),1000,'Forged ledger',auth.uid());
    raise exception 'Direct ledger write unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: administrator authorization, RLS, opt-in privacy, idempotency, and overdraft checks';
