-- Optional Supabase foundation. Run only in your own project after review.
-- No planner contents are uploaded. No client can award itself points.
begin;

create table public.onestep_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(display_name) between 1 and 40),
  leaderboard_opt_in boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.onestep_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
create table public.onestep_points_ledger (
  event_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  delta integer not null check (delta between -10000 and 10000 and delta <> 0),
  reason text not null check (length(reason) between 3 and 160),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index on public.onestep_points_ledger(user_id, created_at desc);

alter table public.onestep_profiles enable row level security;
alter table public.onestep_admins enable row level security;
alter table public.onestep_points_ledger enable row level security;

revoke all on public.onestep_profiles, public.onestep_admins, public.onestep_points_ledger from anon, authenticated;
grant select, insert, update on public.onestep_profiles to authenticated;
grant select on public.onestep_admins, public.onestep_points_ledger to authenticated;

create policy profile_read_own on public.onestep_profiles for select to authenticated using (auth.uid() = user_id);
create policy profile_insert_own on public.onestep_profiles for insert to authenticated with check (auth.uid() = user_id);
create policy profile_update_own on public.onestep_profiles for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy admin_read_own on public.onestep_admins for select to authenticated using (auth.uid() = user_id);
create policy ledger_read_own on public.onestep_points_ledger for select to authenticated using (auth.uid() = user_id);

-- This owner-backed view deliberately reveals only opt-in display names and totals.
-- It never includes email, task text, app choices, ledger reasons, or user IDs.
create view public.onestep_leaderboard with (security_barrier = true) as
select p.display_name, coalesce(sum(l.delta), 0)::bigint as points
from public.onestep_profiles p
left join public.onestep_points_ledger l on l.user_id = p.user_id
where p.leaderboard_opt_in
group by p.user_id, p.display_name
order by points desc, p.display_name asc
limit 100;
revoke all on public.onestep_leaderboard from anon, authenticated;
grant select on public.onestep_leaderboard to authenticated;

create function public.onestep_admin_adjust_points(target uuid, amount integer, explanation text, event uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  previous public.onestep_points_ledger%rowtype;
  balance bigint;
begin
  if actor is null or not exists (select 1 from public.onestep_admins a where a.user_id = actor) then
    raise exception 'Administrator authorization required' using errcode = '42501';
  end if;
  if target is null or event is null or amount is null or amount = 0 or amount not between -10000 and 10000
     or explanation is null or length(trim(explanation)) not between 3 and 160 then
    raise exception 'Invalid adjustment';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target::text, 0));
  select * into previous from public.onestep_points_ledger where event_id = event;
  if found then
    if previous.user_id <> target or previous.delta <> amount or previous.reason <> trim(explanation) or previous.actor_id <> actor then
      raise exception 'Event ID already used for another adjustment';
    end if;
  else
    select coalesce(sum(delta), 0) into balance from public.onestep_points_ledger where user_id = target;
    if balance + amount < 0 then raise exception 'Insufficient points'; end if;
    insert into public.onestep_points_ledger(event_id,user_id,delta,reason,actor_id)
      values (event,target,amount,trim(explanation),actor);
  end if;
  select coalesce(sum(delta), 0) into balance from public.onestep_points_ledger where user_id = target;
  return balance;
end;
$$;
revoke all on function public.onestep_admin_adjust_points(uuid,integer,text,uuid) from public, anon, authenticated;
grant execute on function public.onestep_admin_adjust_points(uuid,integer,text,uuid) to authenticated;

commit;
