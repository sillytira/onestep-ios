\set ON_ERROR_STOP on
\ir personal-rewards-test.sql
\ir 006_economy_xp.sql
-- The upgrade must preserve all existing permissions and old receipts.
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
delete from public.onestep_personal_tasks where user_id=auth.uid();
delete from public.onestep_points_ledger where user_id=auth.uid() and reason='Self-reported task reward';
delete from public.onestep_screen_time_receipts where user_id=auth.uid();
do $$ declare i integer;c uuid;result jsonb;d uuid:=gen_random_uuid();e uuid:=gen_random_uuid();b bigint;begin
 for i in 1..11 loop
  c:=gen_random_uuid();
  insert into public.onestep_personal_tasks(user_id,client_id,title_hash,reward,eligible_at) values(auth.uid(),c,'v6-task-'||i,100,now()-interval '1 minute');
  update public.onestep_personal_tasks set completed_at=now()-interval '31 seconds' where user_id=auth.uid() and completed_at is not null;
  result:=public.onestep_complete_personal_task(c);
  if (result->>'points')::integer<>(case when i<=10 then 100 else 0 end) then raise exception '1000-point earnings cap failed';end if;
 end loop;
 if (public.onestep_economy_status()->>'earned_today')::integer<>1000 then raise exception 'Status disagrees with ledger';end if;
 if (select earned_points from public.onestep_rankings('points') where handle='member')<>1000 then raise exception 'Leaderboard cap failed';end if;
 b:=public.onestep_my_balance();
 begin perform public.onestep_redeem_screen_time(e,d,1,2);raise exception 'Wrong exchange rate accepted' using errcode='P0002';exception when raise_exception then null;end;
 perform public.onestep_redeem_screen_time(e,d,1,1);perform public.onestep_redeem_screen_time(e,d,1,1);
 if public.onestep_my_balance()<>b-1 then raise exception 'One minute did not cost exactly one point once';end if;
 perform public.onestep_redeem_screen_time(gen_random_uuid(),gen_random_uuid(),999,999);
 begin perform public.onestep_redeem_screen_time(gen_random_uuid(),gen_random_uuid(),1,1);raise exception 'Cross-device daily redemption cap bypassed' using errcode='P0002';exception when raise_exception then null;end;
 if (public.onestep_economy_status()->>'minutes_remaining')::integer<>0 then raise exception 'Wrong minutes remaining';end if;
end $$;

-- XP is independent: it cannot affect points, public membership, or redemption.
do $$ declare i integer;key text;v jsonb;b bigint:=public.onestep_my_balance();begin
 for i in 1..101 loop
  update public.onestep_xp_events set created_at=now()-interval '6 seconds' where user_id=auth.uid();
  key:='task.'||gen_random_uuid()::text;
  v:=public.onestep_claim_xp(key,'task');
  if (v->>'xp')::integer<>(case when i<=100 then 10 else 0 end) then raise exception 'XP daily cap failed';end if;
  if i=1 then
   v:=public.onestep_claim_xp(key,'task');if v->>'status'<>'recorded' then raise exception 'XP replay not idempotent';end if;
   v:=public.onestep_claim_xp('task.'||gen_random_uuid()::text,'task');if v->>'status'<>'pending' then raise exception 'XP rate filter failed';end if;
  end if;
 end loop;
 if public.onestep_my_balance()<>b then raise exception 'XP affected spendable points';end if;
 if (public.onestep_economy_status()->>'xp_total')::integer<>1000 then raise exception 'Wrong XP total';end if;
 if exists(select 1 from public.onestep_xp_rankings() where handle='member') then raise exception 'XP opted in automatically';end if;
 perform public.onestep_set_xp_public(true);
 if (select earned_xp from public.onestep_xp_rankings() where handle='member')<>1000 then raise exception 'Separate XP ranking failed';end if;
 perform public.onestep_set_xp_public(false);
end $$;

select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
do $$ begin
 begin perform public.onestep_set_screen_policy('55555555-5555-4555-8555-555555555555',true,2,1000);raise exception 'Parent changed fixed exchange rate' using errcode='P0002';exception when raise_exception then null;end;
 perform public.onestep_set_screen_policy('55555555-5555-4555-8555-555555555555',true,1,16);
end $$;
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
set role authenticated;
do $$ declare b bigint:=public.onestep_my_balance();begin
 perform public.onestep_redeem_screen_time(gen_random_uuid(),gen_random_uuid(),1,1);
 if public.onestep_my_balance()<>b-1 then raise exception 'Child minute price failed';end if;
 begin perform public.onestep_redeem_screen_time(gen_random_uuid(),gen_random_uuid(),1,1);raise exception 'Lower parent daily allowance bypassed' using errcode='P0002';exception when raise_exception then null;end;
 perform public.onestep_claim_xp('routine.'||gen_random_uuid()::text||'.2026-11-12','routine');
 begin perform public.onestep_set_xp_public(true);raise exception 'Child joined XP ranking' using errcode='P0002';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.onestep_xp_events where user_id<>auth.uid()) then raise exception 'XP privacy failed';end if;
 begin insert into public.onestep_xp_events values(auth.uid(),'fake','task',10,now());raise exception 'Direct XP write allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Parent task approval also respects the shared daily earned-points ceiling.
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
do $$ declare a uuid;b uuid;begin
 a:=public.onestep_assign_family_task('55555555-5555-4555-8555-555555555555','First substantial task',600);
 b:=public.onestep_assign_family_task('55555555-5555-4555-8555-555555555555','Second substantial task',600);
 update public.onestep_family_tasks set status='submitted' where id in(a,b);
 perform public.onestep_review_family_task(a,true);perform public.onestep_review_family_task(a,true);
 begin perform public.onestep_review_family_task(b,true);raise exception 'Parent reward cap bypassed' using errcode='P0002';exception when raise_exception then null;end;
 if (select status from public.onestep_family_tasks where id=b)<>'submitted' then raise exception 'Capped approval lost task';end if;
end $$;
set role anon;
do $$ begin
 begin perform public.onestep_economy_status();raise exception 'Anonymous economy access' using errcode='P0002';exception when insufficient_privilege then null;end;
 begin perform public.onestep_xp_rankings();raise exception 'Anonymous XP access' using errcode='P0002';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: fixed exchange, 1000 earned/spent caps, child allowance, separate capped XP, opt-in rankings, privacy and exactly-once rewards';
