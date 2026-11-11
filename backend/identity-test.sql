\set ON_ERROR_STOP on
\ir family-test.sql
alter table auth.users add column email text,add column raw_user_meta_data jsonb default '{}'::jsonb,add column created_at timestamptz default now();
\ir 003_beta_identity.sql
select replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','') as owner_code \gset
insert into public.onestep_beta_invites(code_hash,kind,email)
  values(encode(sha256(convert_to(:'owner_code','UTF8')),'hex'),'owner','owner@example.invalid');
do $$ begin
  begin
    insert into auth.users(id,email) values(gen_random_uuid(),'bypass@example.invalid');
    raise exception 'Signup bypassed beta gate' using errcode='P0002';
  exception when raise_exception then null; end;
end $$;
insert into auth.users(id,email,raw_user_meta_data) values('44444444-4444-4444-8444-444444444444','owner@example.invalid',jsonb_build_object('beta_key',:'owner_code','username','ignored'));
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
do $$ begin
  if not public.onestep_is_admin() then raise exception 'Owner admin not installed'; end if;
  if (select handle from public.onestep_profiles where user_id=auth.uid())<>'meow' then raise exception 'Wrong owner handle'; end if;
end $$;
select public.onestep_issue_beta_key('kids','kid@example.invalid') as kid_code \gset
select public.onestep_issue_beta_key('normal','member@example.invalid') as normal_code \gset
reset role;
insert into auth.users(id,email,raw_user_meta_data) values('55555555-5555-4555-8555-555555555555','kid@example.invalid',jsonb_build_object('beta_key',:'kid_code','username','ignored','is_admin',true));
select set_config('test.normal_code',:'normal_code',false);
do $$ begin
  begin
    insert into auth.users(id,email,raw_user_meta_data) values(gen_random_uuid(),'member@example.invalid',jsonb_build_object('beta_key',current_setting('test.normal_code'),'username','tira'));
    raise exception 'Reserved username claimed' using errcode='P0002';
  exception when raise_exception then null; end;
end $$;
insert into auth.users(id,email,raw_user_meta_data) values('66666666-6666-4666-8666-666666666666','member@example.invalid',jsonb_build_object('beta_key',:'normal_code','username','member'));
set role authenticated;
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
do $$ begin
  if public.onestep_is_admin() then raise exception 'Editable metadata granted admin'; end if;
  begin
    perform public.onestep_update_profile('Public kid','publickid',true);
    raise exception 'Kid enabled public profile' using errcode='P0002';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
select public.onestep_update_profile('Member','member',true);
do $$ begin
  if exists(select 1 from public.onestep_leaderboard where handle='ignored') then raise exception 'Kid leaked into leaderboard'; end if;
end $$;
reset role;
select 'PASS: beta gating, owner binding, private child identities, reserved handles, and metadata privilege rejection';
