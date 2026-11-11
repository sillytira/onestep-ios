-- Run after 001_points_foundation.sql. All points are virtual, never purchasable.
begin;
create table public.onestep_families (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null check (length(name) between 1 and 60),
  created_at timestamptz not null default now()
);
create table public.onestep_children (
  child_id uuid primary key references auth.users(id) on delete cascade,
  family_id uuid not null references public.onestep_families(id) on delete cascade,
  nickname text not null check (length(nickname) between 1 and 40)
);
create table public.onestep_family_invites (
  code_hash text primary key,
  family_id uuid not null references public.onestep_families(id) on delete cascade,
  expires_at timestamptz not null
);
create table public.onestep_family_tasks (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.onestep_families(id) on delete cascade,
  child_id uuid not null references public.onestep_children(child_id) on delete cascade,
  title text not null check (length(title) between 1 and 160),
  points integer not null check (points between 1 and 1000),
  status text not null default 'assigned' check (status in ('assigned','submitted','approved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.onestep_family_tasks(child_id,updated_at desc);
alter table public.onestep_families enable row level security;
alter table public.onestep_children enable row level security;
alter table public.onestep_family_invites enable row level security;
alter table public.onestep_family_tasks enable row level security;
revoke all on public.onestep_families,public.onestep_children,public.onestep_family_invites,public.onestep_family_tasks from public,anon,authenticated;
grant select on public.onestep_families,public.onestep_children,public.onestep_family_tasks to authenticated;
create policy family_parent_read on public.onestep_families for select to authenticated using (parent_id=auth.uid());
create policy children_family_read on public.onestep_children for select to authenticated using (
  child_id=auth.uid() or exists(select 1 from public.onestep_families f where f.id=family_id and f.parent_id=auth.uid())
);
create policy family_task_read on public.onestep_family_tasks for select to authenticated using (
  child_id=auth.uid() or exists(select 1 from public.onestep_families f where f.id=family_id and f.parent_id=auth.uid())
);

create function public.onestep_create_family(family_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare family uuid; actor uuid:=auth.uid(); begin
  if actor is null then raise exception 'Sign in first' using errcode='42501'; end if;
  if exists(select 1 from public.onestep_children where child_id=actor) then raise exception 'A child account cannot create a parent family' using errcode='42501'; end if;
  insert into public.onestep_families(parent_id,name) values(actor,trim(family_name)) returning id into family;
  return family;
end $$;

create function public.onestep_create_family_invite() returns text
language plpgsql security definer set search_path='' as $$
declare family uuid; code text; begin
  select id into family from public.onestep_families where parent_id=auth.uid();
  if family is null then raise exception 'Parent authorization required' using errcode='42501'; end if;
  code:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
  delete from public.onestep_family_invites where family_id=family;
  insert into public.onestep_family_invites values(encode(sha256(convert_to(code,'UTF8')),'hex'),family,now()+interval '10 minutes');
  return code;
end $$;

create function public.onestep_accept_family_invite(invite_code text, child_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare family uuid; actor uuid:=auth.uid(); begin
  if actor is null then raise exception 'Sign in first' using errcode='42501'; end if;
  if length(invite_code)<>64 then raise exception 'Invalid or expired invitation'; end if;
  if exists(select 1 from public.onestep_families where parent_id=actor) then raise exception 'Use a separate child account' using errcode='42501'; end if;
  delete from public.onestep_family_invites
    where code_hash=encode(sha256(convert_to(invite_code,'UTF8')),'hex') and expires_at>now() returning family_id into family;
  if family is null then raise exception 'Invalid or expired invitation'; end if;
  insert into public.onestep_children(child_id,family_id,nickname) values(actor,family,trim(child_name));
  return family;
end $$;

create function public.onestep_assign_family_task(child uuid, task_title text, reward integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare family uuid; task uuid; begin
  select f.id into family from public.onestep_families f join public.onestep_children c on c.family_id=f.id
    where f.parent_id=auth.uid() and c.child_id=child;
  if family is null then raise exception 'Linked parent authorization required' using errcode='42501'; end if;
  insert into public.onestep_family_tasks(family_id,child_id,title,points) values(family,child,trim(task_title),reward) returning id into task;
  return task;
end $$;

create function public.onestep_submit_family_task(task uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  update public.onestep_family_tasks set status='submitted',updated_at=now()
    where id=task and child_id=auth.uid() and status='assigned';
  if not found then raise exception 'Assigned task not found or already submitted'; end if;
end $$;

create function public.onestep_review_family_task(task uuid, approve boolean) returns void
language plpgsql security definer set search_path='' as $$
declare entry public.onestep_family_tasks%rowtype; actor uuid:=auth.uid(); begin
  select t.* into entry from public.onestep_family_tasks t join public.onestep_families f on f.id=t.family_id
    where t.id=task and f.parent_id=actor for update of t;
  if not found then raise exception 'Linked parent authorization required' using errcode='42501'; end if;
  if entry.status='approved' and approve then return; end if;
  if entry.status<>'submitted' then raise exception 'Task is not waiting for review'; end if;
  if approve then
    perform pg_advisory_xact_lock(hashtextextended(entry.child_id::text,0));
    insert into public.onestep_points_ledger(event_id,user_id,delta,reason,actor_id)
      values(entry.id,entry.child_id,entry.points,'Parent-approved task',actor);
  end if;
  update public.onestep_family_tasks set status=case when approve then 'approved' else 'assigned' end,updated_at=now() where id=entry.id;
end $$;

-- Balance is computed from the ledger. It cannot be assigned by a client.
create function public.onestep_my_balance() returns bigint language sql stable security invoker set search_path='' as $$
  select coalesce(sum(delta),0)::bigint from public.onestep_points_ledger where user_id=auth.uid()
$$;

revoke all on function public.onestep_create_family(text),public.onestep_create_family_invite(),public.onestep_accept_family_invite(text,text),
  public.onestep_assign_family_task(uuid,text,integer),public.onestep_submit_family_task(uuid),public.onestep_review_family_task(uuid,boolean),public.onestep_my_balance() from public,anon,authenticated;
grant execute on function public.onestep_create_family(text),public.onestep_create_family_invite(),public.onestep_accept_family_invite(text,text),
  public.onestep_assign_family_task(uuid,text,integer),public.onestep_submit_family_task(uuid),public.onestep_review_family_task(uuid,boolean),public.onestep_my_balance() to authenticated;
commit;
