-- Personal self-reported rewards, bounded weekly rankings and idempotent app-time purchases.
begin;
create table public.onestep_personal_tasks (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 client_id uuid not null, title_hash text not null, reward integer not null check(reward between 0 and 100),
 created_at timestamptz not null default now(), eligible_at timestamptz not null default(now()+interval '1 minute'),
 completed_at timestamptz, awarded integer not null default 0, counted boolean not null default false,
 unique(user_id,client_id)
);
create index on public.onestep_personal_tasks(user_id,completed_at);
alter table public.onestep_personal_tasks enable row level security;
revoke all on public.onestep_personal_tasks from public,anon,authenticated;
grant select on public.onestep_personal_tasks to authenticated;
create policy personal_read on public.onestep_personal_tasks for select to authenticated using(user_id=auth.uid());

create function public.onestep_register_personal_task(client uuid, task_title text, task_points integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); entry public.onestep_personal_tasks%rowtype; fingerprint text; begin
 if not exists(select 1 from public.onestep_account_kinds where user_id=actor and kind in('normal','parent','owner')) then raise exception 'Personal rewards require a normal or parent account' using errcode='42501'; end if;
 if client is null or task_points is null or task_points not between 0 and 100 or task_title is null or length(trim(task_title)) not between 3 and 160 then raise exception 'Use a 3–160 character title and 0–100 points'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 fingerprint:=encode(sha256(convert_to(lower(regexp_replace(trim(task_title),'\s+',' ','g')),'UTF8')),'hex');
 select * into entry from public.onestep_personal_tasks where user_id=actor and client_id=client for update;
 if found then
   if entry.completed_at is not null then return entry.id; end if;
   if entry.title_hash<>fingerprint or entry.reward<>task_points then update public.onestep_personal_tasks set title_hash=fingerprint,reward=task_points,eligible_at=now()+interval '1 minute' where id=entry.id; end if;
   return entry.id;
 end if;
 if (select count(*) from public.onestep_personal_tasks where user_id=actor and created_at >= date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')>=100 then raise exception 'Daily registration limit reached'; end if;
 if exists(select 1 from public.onestep_personal_tasks where user_id=actor and created_at>now()-interval '5 seconds') then raise exception 'Wait a few seconds before registering another reward task'; end if;
 insert into public.onestep_personal_tasks(user_id,client_id,title_hash,reward) values(actor,client,fingerprint,task_points) returning id into client;
 return client;
end $$;

create function public.onestep_complete_personal_task(client uuid) returns jsonb
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
 select count(*) filter(where counted),coalesce(sum(awarded),0) into total_tasks,total_points from public.onestep_personal_tasks where user_id=actor and completed_at>=day_start;
 if exists(select 1 from public.onestep_personal_tasks where user_id=actor and title_hash=entry.title_hash and completed_at>=day_start) then why:='duplicate';
 elsif total_tasks>=20 then why:='task_limit';
 else eligible:=true; credit:=least(entry.reward,greatest(0,500-total_points)); if credit<entry.reward then why:='points_limit'; end if;
 end if;
 update public.onestep_personal_tasks set completed_at=now(),awarded=credit,counted=eligible where id=entry.id;
 if credit>0 then insert into public.onestep_points_ledger(event_id,user_id,delta,reason,actor_id) values(entry.id,actor,credit,'Self-reported task reward',actor); end if;
 return jsonb_build_object('status',why,'points',credit,'counted',eligible);
end $$;

-- Old clients keep the original three columns, but points now mean task-earned points this week.
create or replace view public.onestep_leaderboard with(security_barrier=true) as
 select p.display_name,coalesce(sum(t.awarded),0)::bigint as points,p.handle
 from public.onestep_profiles p
 left join public.onestep_personal_tasks t on t.user_id=p.user_id and t.counted and t.completed_at>=date_trunc('week',now() at time zone 'UTC') at time zone 'UTC'
 where p.leaderboard_opt_in and exists(select 1 from public.onestep_account_kinds k where k.user_id=p.user_id and k.kind in('normal','parent','owner'))
 and not exists(select 1 from public.onestep_children c where c.child_id=p.user_id)
 group by p.user_id,p.display_name,p.handle order by points desc,p.handle limit 100;

create function public.onestep_rankings(metric text default 'tasks') returns table(display_name text,handle text,completed_tasks bigint,earned_points bigint)
language plpgsql stable security definer set search_path='' as $$ begin
 if auth.uid() is null then raise exception 'Sign in first' using errcode='42501'; end if;
 if metric not in('tasks','points') then raise exception 'Invalid ranking metric'; end if;
 return query select p.display_name,p.handle,count(t.id)::bigint,coalesce(sum(t.awarded),0)::bigint
 from public.onestep_profiles p
 left join public.onestep_personal_tasks t on t.user_id=p.user_id and t.counted and t.completed_at>=date_trunc('week',now() at time zone 'UTC') at time zone 'UTC'
 where p.leaderboard_opt_in and exists(select 1 from public.onestep_account_kinds k where k.user_id=p.user_id and k.kind in('normal','parent','owner'))
 and not exists(select 1 from public.onestep_children c where c.child_id=p.user_id)
 group by p.user_id,p.display_name,p.handle
 order by case when metric='tasks' then count(t.id)::bigint else coalesce(sum(t.awarded),0)::bigint end desc,p.handle limit 100;
end $$;

create table public.onestep_screen_time_policies (
 user_id uuid primary key references auth.users(id),approved_by uuid not null references auth.users(id),
 enabled boolean not null default false,cost_per_minute integer not null check(cost_per_minute between 1 and 10),
 daily_minutes integer not null check(daily_minutes between 15 and 120)
);
alter table public.onestep_screen_time_policies enable row level security;
revoke all on public.onestep_screen_time_policies from public,anon,authenticated;
grant select on public.onestep_screen_time_policies to authenticated;
create policy screen_policy_read on public.onestep_screen_time_policies for select to authenticated using(user_id=auth.uid() or approved_by=auth.uid());
create function public.onestep_set_screen_policy(child uuid,allow_unlock boolean,minute_cost integer default 1,day_minutes integer default 120) returns void
language plpgsql security definer set search_path='' as $$ begin
 if not exists(select 1 from public.onestep_children c join public.onestep_families f on f.id=c.family_id where c.child_id=child and c.active and f.parent_id=auth.uid()) then raise exception 'Linked parent authorization required' using errcode='42501'; end if;
 insert into public.onestep_screen_time_policies(user_id,approved_by,enabled,cost_per_minute,daily_minutes) values(child,auth.uid(),allow_unlock,minute_cost,day_minutes)
 on conflict(user_id) do update set approved_by=excluded.approved_by,enabled=excluded.enabled,cost_per_minute=excluded.cost_per_minute,daily_minutes=excluded.daily_minutes;
end $$;
create table public.onestep_screen_time_receipts (
 id uuid primary key, user_id uuid not null references auth.users(id),device_id uuid not null,
 minutes integer not null check(minutes in(15,30,60)),cost integer not null,
 created_at timestamptz not null default now(),expires_at timestamptz not null
);
alter table public.onestep_screen_time_receipts enable row level security;
revoke all on public.onestep_screen_time_receipts from public,anon,authenticated;
grant select on public.onestep_screen_time_receipts to authenticated;
create policy receipt_read on public.onestep_screen_time_receipts for select to authenticated using(user_id=auth.uid());
create function public.onestep_redeem_screen_time(event uuid,device uuid,duration integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); receipt public.onestep_screen_time_receipts%rowtype; balance bigint; account_kind text; price integer:=1; day_limit integer:=120; begin
 select kind into account_kind from public.onestep_account_kinds where user_id=actor;
 if account_kind is null then raise exception 'Enrolled account required' using errcode='42501'; end if;
 if account_kind='kids' then
   select p.cost_per_minute,p.daily_minutes into price,day_limit from public.onestep_screen_time_policies p
    join public.onestep_children c on c.child_id=p.user_id and c.active join public.onestep_families f on f.id=c.family_id and f.parent_id=p.approved_by
    where p.user_id=actor and p.enabled;
   if price is null then raise exception 'Your parent must enable a points-unlock policy' using errcode='42501'; end if;
 end if;
 if event is null or device is null or duration is null or duration not in(15,30,60) then raise exception 'Choose 15, 30 or 60 minutes'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 select * into receipt from public.onestep_screen_time_receipts where id=event;
 if found then
  if receipt.user_id<>actor or receipt.device_id<>device or receipt.minutes<>duration then raise exception 'Receipt identifier already used'; end if;
  return to_jsonb(receipt);
 end if;
 if exists(select 1 from public.onestep_screen_time_receipts where user_id=actor and device_id=device and expires_at>now()) then raise exception 'This device already has an active unlock'; end if;
 if (select coalesce(sum(minutes),0) from public.onestep_screen_time_receipts where user_id=actor and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')+duration>day_limit then raise exception 'Daily unlock limit reached'; end if;
 select coalesce(sum(delta),0) into balance from public.onestep_points_ledger where user_id=actor;
 if balance<duration*price then raise exception 'Not enough points'; end if;
 insert into public.onestep_screen_time_receipts(id,user_id,device_id,minutes,cost,expires_at) values(event,actor,device,duration,duration*price,now()+make_interval(mins=>duration)) returning * into receipt;
 insert into public.onestep_points_ledger(event_id,user_id,delta,reason,actor_id) values(event,actor,-duration*price,'Screen Time unlock',actor);
 return to_jsonb(receipt);
end $$;
revoke all on function public.onestep_register_personal_task(uuid,text,integer),public.onestep_complete_personal_task(uuid),public.onestep_rankings(text),public.onestep_redeem_screen_time(uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.onestep_register_personal_task(uuid,text,integer),public.onestep_complete_personal_task(uuid),public.onestep_rankings(text),public.onestep_redeem_screen_time(uuid,uuid,integer) to authenticated;
revoke all on function public.onestep_set_screen_policy(uuid,boolean,integer,integer) from public,anon,authenticated;
grant execute on function public.onestep_set_screen_policy(uuid,boolean,integer,integer) to authenticated;
commit;
