\set ON_ERROR_STOP on
\ir parent-controls-test.sql
\ir 005_personal_rewards.sql
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
set role authenticated;
select public.onestep_register_personal_task('11111111-aaaa-4111-8111-111111111111','  A real task  ',100);
do $$ begin
 if (public.onestep_complete_personal_task('11111111-aaaa-4111-8111-111111111111')->>'status')<>'pending' then raise exception 'Task-age filter failed'; end if;
 begin perform public.onestep_register_personal_task(gen_random_uuid(),'Bad reward',101);raise exception 'Reward cap bypassed' using errcode='P0002';exception when raise_exception then null;end;
 begin update public.onestep_personal_tasks set reward=100;raise exception 'Direct writes allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
delete from public.onestep_personal_tasks where user_id='66666666-6666-4666-8666-666666666666';
do $$ declare i integer; c uuid; result jsonb; before_balance bigint; e uuid:=gen_random_uuid(); d uuid:=gen_random_uuid(); begin
 for i in 1..21 loop
  c:=gen_random_uuid();
  insert into public.onestep_personal_tasks(user_id,client_id,title_hash,reward,created_at,eligible_at) values('66666666-6666-4666-8666-666666666666',c,'synthetic-hash-'||i,100,now()-interval '2 minutes',now()-interval '1 minute');
  update public.onestep_personal_tasks set completed_at=now()-interval '31 seconds' where user_id=auth.uid() and completed_at is not null;
  result:=public.onestep_complete_personal_task(c);
  if i<=5 and (result->>'points')::integer<>100 then raise exception 'Expected bounded award';end if;
  if i>5 and (result->>'points')::integer<>0 then raise exception 'Daily points cap bypassed';end if;
  if i=21 and (result->>'counted')::boolean then raise exception 'Daily task count cap bypassed';end if;
  perform public.onestep_complete_personal_task(c);
 end loop;
 if (select sum(awarded) from public.onestep_personal_tasks where user_id=auth.uid())<>500 then raise exception 'Wrong earned total';end if;
 if (select count(*) from public.onestep_personal_tasks where user_id=auth.uid() and counted)<>20 then raise exception 'Wrong counted total';end if;
 before_balance:=public.onestep_my_balance();
 perform public.onestep_redeem_screen_time(e,d,15);perform public.onestep_redeem_screen_time(e,d,15);
 if public.onestep_my_balance()<>before_balance-15 then raise exception 'Redemption not exactly once';end if;
 begin perform public.onestep_redeem_screen_time(gen_random_uuid(),d,15);raise exception 'Concurrent unlock allowed' using errcode='P0002';exception when raise_exception then null;end;
 begin perform public.onestep_redeem_screen_time(gen_random_uuid(),gen_random_uuid(),60);perform public.onestep_redeem_screen_time(gen_random_uuid(),gen_random_uuid(),60);raise exception 'Daily minutes cap bypassed' using errcode='P0002';exception when raise_exception then null;end;
end $$;
select public.onestep_update_profile('Member','member',true);
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select public.onestep_admin_adjust_points('66666666-6666-4666-8666-666666666666',1000,'Synthetic admin adjustment',gen_random_uuid());
do $$ begin if (select earned_points from public.onestep_rankings('points') where handle='member')<>500 then raise exception 'Admin credit counted as earned';end if;end $$;
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
set role authenticated;
do $$ begin
 begin perform public.onestep_register_personal_task(gen_random_uuid(),'Kid self award',100);raise exception 'Child self-awarded' using errcode='P0002';exception when insufficient_privilege then null;end;
 begin perform public.onestep_set_screen_policy(auth.uid(),true);raise exception 'Child changed policy' using errcode='P0002';exception when insufficient_privilege then null;end;
 begin perform public.onestep_redeem_screen_time(gen_random_uuid(),gen_random_uuid(),15);raise exception 'Child redeemed without policy' using errcode='P0002';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.onestep_personal_tasks) then raise exception 'Child read another account tasks';end if;
end $$;
reset role;
update public.onestep_children set active=true where child_id='55555555-5555-4555-8555-555555555555';
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select public.onestep_set_screen_policy('55555555-5555-4555-8555-555555555555',true,2,30);
select public.onestep_admin_adjust_points('55555555-5555-4555-8555-555555555555',100,'Synthetic child funding',gen_random_uuid());
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
set role authenticated;
select public.onestep_redeem_screen_time(gen_random_uuid(),gen_random_uuid(),15);
do $$ begin if public.onestep_my_balance()<>70 then raise exception 'Parent price not enforced';end if;end $$;
reset role;
select 'PASS: bounded self rewards, anti-spam, weekly rankings, private children and idempotent policy-bound redemption';
