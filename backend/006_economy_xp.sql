-- Upgrade 005 in place. Virtual points and non-spendable XP have separate ledgers.
begin;
alter table public.onestep_screen_time_policies drop constraint onestep_screen_time_policies_cost_per_minute_check;
update public.onestep_screen_time_policies set cost_per_minute=1;
alter table public.onestep_screen_time_policies add constraint onestep_screen_time_policies_cost_per_minute_check check(cost_per_minute=1);
alter table public.onestep_screen_time_policies drop constraint onestep_screen_time_policies_daily_minutes_check;
alter table public.onestep_screen_time_policies add constraint onestep_screen_time_policies_daily_minutes_check check(daily_minutes between 1 and 1000);
alter table public.onestep_screen_time_receipts drop constraint onestep_screen_time_receipts_minutes_check;
alter table public.onestep_screen_time_receipts add constraint onestep_screen_time_receipts_minutes_check check(minutes between 1 and 1000);
create or replace function public.onestep_complete_personal_task(client uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); entry public.onestep_personal_tasks%rowtype; day_start timestamptz:=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 last_claim timestamptz; total_tasks integer; total_points integer; credit integer:=0; eligible boolean:=false; why text:='credited'; begin
 if not exists(select 1 from public.onestep_account_kinds where user_id=actor and kind in('normal','parent','owner')) then raise exception 'Personal rewards are not available to child accounts' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 select * into entry from public.onestep_personal_tasks where user_id=actor and client_id=client for update;
 if not found then raise exception 'Register this task first'; end if;
 if entry.completed_at is not null then return jsonb_build_object('status','recorded','points',entry.awarded,'counted',entry.counted); end if;
 select max(completed_at) into last_claim from public.onestep_personal_tasks where user_id=actor and counted;
 if entry.eligible_at>now() or last_claim>now()-interval '30 seconds' then return jsonb_build_object('status','pending','retry_at',greatest(entry.eligible_at,coalesce(last_claim+interval '30 seconds',entry.eligible_at))); end if;
 select count(*) filter(where counted) into total_tasks from public.onestep_personal_tasks where user_id=actor and completed_at>=day_start;
 select coalesce(sum(delta),0) into total_points from public.onestep_points_ledger where user_id=actor and delta>0 and reason in('Self-reported task reward','Parent-approved task') and created_at>=day_start;
 if exists(select 1 from public.onestep_personal_tasks where user_id=actor and title_hash=entry.title_hash and completed_at>=day_start) then why:='duplicate';
 elsif total_tasks>=20 then why:='task_limit';
 else eligible:=true; credit:=least(entry.reward,greatest(0,1000-total_points)); if credit<entry.reward then why:='points_limit'; end if;
 end if;
 update public.onestep_personal_tasks set completed_at=now(),awarded=credit,counted=eligible where id=entry.id;
 if credit>0 then insert into public.onestep_points_ledger(event_id,user_id,delta,reason,actor_id) values(entry.id,actor,credit,'Self-reported task reward',actor); end if;
 return jsonb_build_object('status',why,'points',credit,'counted',eligible);
end $$;
create or replace function public.onestep_review_family_task(task uuid, approve boolean) returns void
language plpgsql security definer set search_path='' as $$
declare entry public.onestep_family_tasks%rowtype; actor uuid:=auth.uid(); begin
  select t.* into entry from public.onestep_family_tasks t join public.onestep_families f on f.id=t.family_id
    where t.id=task and f.parent_id=actor for update of t;
  if not found then raise exception 'Linked parent authorization required' using errcode='42501'; end if;
  if entry.status='approved' and approve then return; end if;
  if entry.status<>'submitted' then raise exception 'Task is not waiting for review'; end if;
  if approve then
    perform pg_advisory_xact_lock(hashtextextended(entry.child_id::text,0));
    if (select coalesce(sum(delta),0) from public.onestep_points_ledger where user_id=entry.child_id and delta>0 and reason in('Parent-approved task','Self-reported task reward') and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')+entry.points>1000 then raise exception 'Daily earned-points limit is 1000. This task stays submitted for later approval.'; end if;
    insert into public.onestep_points_ledger(event_id,user_id,delta,reason,actor_id)
      values(entry.id,entry.child_id,entry.points,'Parent-approved task',actor);
  end if;
  update public.onestep_family_tasks set status=case when approve then 'approved' else 'assigned' end,updated_at=now() where id=entry.id;
end $$;
create or replace function public.onestep_set_screen_policy(child uuid,allow_unlock boolean,minute_cost integer default 1,day_minutes integer default 120) returns void
language plpgsql security definer set search_path='' as $$ begin
 if minute_cost is distinct from 1 or day_minutes is null or day_minutes not between 1 and 1000 then raise exception '1 point equals 1 minute; choose a daily limit from 1 to 1000 minutes'; end if;
 if not exists(select 1 from public.onestep_children c join public.onestep_families f on f.id=c.family_id where c.child_id=child and c.active and f.parent_id=auth.uid()) then raise exception 'Linked parent authorization required' using errcode='42501'; end if;
 insert into public.onestep_screen_time_policies(user_id,approved_by,enabled,cost_per_minute,daily_minutes) values(child,auth.uid(),allow_unlock,1,day_minutes)
 on conflict(user_id) do update set approved_by=excluded.approved_by,enabled=excluded.enabled,cost_per_minute=1,daily_minutes=excluded.daily_minutes;
end $$;
create or replace function public.onestep_redeem_screen_time(event uuid,device uuid,duration integer,expected_cost integer default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); receipt public.onestep_screen_time_receipts%rowtype; balance bigint; account_kind text; price integer:=1; day_limit integer:=1000; begin
 select kind into account_kind from public.onestep_account_kinds where user_id=actor;
 if account_kind is null then raise exception 'Enrolled account required' using errcode='42501'; end if;
 if event is null or device is null or duration is null or duration not between 1 and 1000 then raise exception 'Choose 1 to 1000 minutes'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 select * into receipt from public.onestep_screen_time_receipts where id=event;
 if found then
  if receipt.user_id<>actor or receipt.device_id<>device or receipt.minutes<>duration then raise exception 'Receipt identifier already used'; end if;
  return to_jsonb(receipt);
 end if;
 if account_kind='kids' then
   select p.cost_per_minute,p.daily_minutes into price,day_limit from public.onestep_screen_time_policies p
    join public.onestep_children c on c.child_id=p.user_id and c.active join public.onestep_families f on f.id=c.family_id and f.parent_id=p.approved_by
    where p.user_id=actor and p.enabled;
   if price is null then raise exception 'Your parent must enable a points-unlock policy' using errcode='42501'; end if;
 end if;
 price:=1;
 if expected_cost is not null and expected_cost<>duration then raise exception 'Unlock price changed. Refresh the policy and confirm the new cost.'; end if;
 if exists(select 1 from public.onestep_screen_time_receipts where user_id=actor and device_id=device and expires_at>now()) then raise exception 'This device already has an active unlock'; end if;
 if (select coalesce(sum(minutes),0) from public.onestep_screen_time_receipts where user_id=actor and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')+duration>day_limit then raise exception 'Daily unlock limit reached'; end if;
 select coalesce(sum(delta),0) into balance from public.onestep_points_ledger where user_id=actor;
 if balance<duration*price then raise exception 'Not enough points'; end if;
 insert into public.onestep_screen_time_receipts(id,user_id,device_id,minutes,cost,expires_at) values(event,actor,device,duration,duration*price,now()+make_interval(mins=>duration)) returning * into receipt;
 insert into public.onestep_points_ledger(event_id,user_id,delta,reason,actor_id) values(event,actor,-duration*price,'Screen Time unlock',actor);
 return to_jsonb(receipt);
end $$;

alter table public.onestep_profiles add column xp_leaderboard_opt_in boolean not null default false;
create table public.onestep_xp_events (
 user_id uuid not null references auth.users(id),event_key text not null,kind text not null check(kind in('task','routine')),
 awarded integer not null check(awarded between 0 and 10),created_at timestamptz not null default now(),
 primary key(user_id,event_key)
);
create index on public.onestep_xp_events(user_id,created_at);
alter table public.onestep_xp_events enable row level security;
revoke all on public.onestep_xp_events from public,anon,authenticated;
grant select on public.onestep_xp_events to authenticated;
create policy xp_own_read on public.onestep_xp_events for select to authenticated using(user_id=auth.uid());

create function public.onestep_claim_xp(event_key text,event_kind text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); saved public.onestep_xp_events%rowtype; amount integer; last_at timestamptz; begin
 if not exists(select 1 from public.onestep_account_kinds where user_id=actor) then raise exception 'Enrolled account required' using errcode='42501'; end if;
 if event_kind is null or event_kind not in('task','routine') or event_key is null or length(event_key)>90
 or (event_kind='task' and event_key !~ '^task\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
 or (event_kind='routine' and event_key !~ '^routine\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[0-9]{4}-[0-9]{2}-[0-9]{2}$') then raise exception 'Invalid XP completion'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 select * into saved from public.onestep_xp_events x where x.user_id=actor and x.event_key=onestep_claim_xp.event_key;
 if found then return jsonb_build_object('status','recorded','xp',saved.awarded); end if;
 select max(created_at) into last_at from public.onestep_xp_events where user_id=actor;
 if last_at>now()-interval '5 seconds' then return jsonb_build_object('status','pending','xp',0); end if;
 select least(10,greatest(0,1000-coalesce(sum(awarded),0))) into amount from public.onestep_xp_events where user_id=actor and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 if amount=0 then return jsonb_build_object('status','daily_limit','xp',0); end if;
 insert into public.onestep_xp_events(user_id,event_key,kind,awarded) values(actor,event_key,event_kind,amount);
 return jsonb_build_object('status','credited','xp',amount);
end $$;

create function public.onestep_set_xp_public(opt_in boolean) returns void
language plpgsql security definer set search_path='' as $$ begin
 if opt_in is null or not exists(select 1 from public.onestep_account_kinds where user_id=auth.uid() and kind in('normal','parent','owner')) or exists(select 1 from public.onestep_children where child_id=auth.uid()) then raise exception 'Only non-child accounts can join public rankings' using errcode='42501'; end if;
 update public.onestep_profiles set xp_leaderboard_opt_in=opt_in where user_id=auth.uid();
end $$;
create function public.onestep_xp_rankings() returns table(display_name text,handle text,earned_xp bigint)
language plpgsql stable security definer set search_path='' as $$ begin
 if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
 return query select p.display_name,p.handle,coalesce(sum(x.awarded),0)::bigint from public.onestep_profiles p
 left join public.onestep_xp_events x on x.user_id=p.user_id and x.created_at>=date_trunc('week',now() at time zone 'UTC') at time zone 'UTC'
 where p.xp_leaderboard_opt_in and exists(select 1 from public.onestep_account_kinds k where k.user_id=p.user_id and k.kind in('normal','parent','owner'))
 and not exists(select 1 from public.onestep_children c where c.child_id=p.user_id)
 group by p.user_id,p.display_name,p.handle order by coalesce(sum(x.awarded),0) desc,p.handle limit 100;
end $$;
create function public.onestep_economy_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); k text; day_start timestamptz:=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'; limit_minutes integer:=1000; enabled boolean:=true; used integer; begin
 select kind into k from public.onestep_account_kinds where user_id=actor;
 if k is null then raise exception 'Enrolled account required' using errcode='42501'; end if;
 if k='kids' then
 select p.daily_minutes,p.enabled into limit_minutes,enabled from public.onestep_screen_time_policies p
 join public.onestep_children c on c.child_id=p.user_id and c.active join public.onestep_families f on f.id=c.family_id and f.parent_id=p.approved_by where p.user_id=actor;
 limit_minutes:=coalesce(limit_minutes,0); enabled:=coalesce(enabled,false);
 end if;
 select coalesce(sum(minutes),0) into used from public.onestep_screen_time_receipts where user_id=actor and created_at>=day_start;
 return jsonb_build_object('version',6,'points_per_minute',1,'daily_points_limit',1000,'daily_minutes_limit',limit_minutes,'minutes_remaining',greatest(0,limit_minutes-used),'redemption_enabled',enabled,
 'earned_today',(select coalesce(sum(delta),0) from public.onestep_points_ledger where user_id=actor and delta>0 and reason in('Self-reported task reward','Parent-approved task') and created_at>=day_start),
 'xp_total',(select coalesce(sum(awarded),0) from public.onestep_xp_events where user_id=actor),
 'xp_today',(select coalesce(sum(awarded),0) from public.onestep_xp_events where user_id=actor and created_at>=day_start),
 'xp_opt_in',(select xp_leaderboard_opt_in from public.onestep_profiles where user_id=actor));
end $$;
revoke all on function public.onestep_claim_xp(text,text),public.onestep_set_xp_public(boolean),public.onestep_xp_rankings(),public.onestep_economy_status() from public,anon,authenticated;
grant execute on function public.onestep_claim_xp(text,text),public.onestep_set_xp_public(boolean),public.onestep_xp_rankings(),public.onestep_economy_status() to authenticated;
commit;
