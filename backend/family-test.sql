\set ON_ERROR_STOP on
\ir test.sql
\ir 002_family_services.sql
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.onestep_create_family('Test family');
select public.onestep_create_family_invite() as invite \gset
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.onestep_accept_family_invite(:'invite','Test child');
do $$ begin
  begin
    perform public.onestep_create_family('Forged parent');
    raise exception 'Child became parent' using errcode='P0002';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.onestep_assign_family_task('22222222-2222-4222-8222-222222222222','Fill the water bottle',7) as task \gset
select set_config('test.task',:'task',false);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.onestep_submit_family_task(:'task');
do $$ begin
  if public.onestep_my_balance()<>0 then raise exception 'Points awarded before approval'; end if;
  begin
    perform public.onestep_review_family_task(current_setting('test.task')::uuid,true);
    raise exception 'Child approved own task' using errcode='P0002';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.onestep_review_family_task(:'task',true);
select public.onestep_review_family_task(:'task',true);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $$ begin
  if public.onestep_my_balance()<>7 then raise exception 'Incorrect or duplicated task award'; end if;
end $$;
reset role;
insert into auth.users values('33333333-3333-4333-8333-333333333333');
set role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
do $$ begin
  if (select count(*) from public.onestep_family_tasks)<>0 then raise exception 'Unrelated account saw family tasks'; end if;
  begin
    perform public.onestep_review_family_task(current_setting('test.task')::uuid,true);
    raise exception 'Unrelated parent approved task' using errcode='P0002';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: invitation linking, parent-only fixed rewards, no self approval, idempotent credit, and family isolation';
