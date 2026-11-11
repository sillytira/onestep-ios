-- Invite-only identities. Never seed enrollment plaintext or project keys in source.
begin;
create table public.onestep_account_kinds (
  user_id uuid primary key references auth.users(id) on delete cascade,
  kind text not null check(kind in('normal','parent','kids','owner'))
);
create table public.onestep_beta_invites (
  code_hash text primary key,
  kind text not null check(kind in('normal','parent','kids','owner')),
  email text,
  expires_at timestamptz not null default now()+interval '7 days',
  used_by uuid,
  issued_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check(kind<>'owner' or email is not null)
);
create table public.onestep_enrollments (
  user_id uuid primary key,
  kind text not null,
  email text not null,
  handle text
);
alter table public.onestep_account_kinds enable row level security;
alter table public.onestep_beta_invites enable row level security;
alter table public.onestep_enrollments enable row level security;
revoke all on public.onestep_account_kinds,public.onestep_beta_invites,public.onestep_enrollments from public,anon,authenticated;
grant select on public.onestep_account_kinds to authenticated;
create policy own_account_kind on public.onestep_account_kinds for select to authenticated using(user_id=auth.uid());
alter table public.onestep_profiles add column handle text unique check(handle is null or handle ~ '^[a-z][a-z0-9_]{2,19}$');
revoke insert,update on public.onestep_profiles from authenticated;

-- A database trigger gates every Auth user creation, including direct API calls.
create function public.onestep_enroll_before_auth_insert() returns trigger
language plpgsql security definer set search_path='' as $$
declare invite public.onestep_beta_invites%rowtype; secret text; username text; begin
  secret:=new.raw_user_meta_data->>'beta_key';
  if secret is null or length(secret)<32 or length(secret)>256 then raise exception 'Valid beta enrollment key required'; end if;
  select * into invite from public.onestep_beta_invites
    where code_hash=encode(sha256(convert_to(secret,'UTF8')),'hex') and used_by is null and expires_at>now() for update;
  if not found or (invite.email is not null and invite.email<>lower(trim(new.email))) then raise exception 'Invalid, expired, or wrong-email enrollment key'; end if;
  if invite.kind<>'owner' and exists(select 1 from public.onestep_beta_invites where kind='owner' and email=lower(trim(new.email))) then raise exception 'Owner enrollment required'; end if;
  username:=lower(trim(new.raw_user_meta_data->>'username'));
  if invite.kind='owner' then
    username:='meow';
  elsif invite.kind='kids' then username:=null;
  else
    if username is null or username !~ '^[a-z][a-z0-9_]{2,19}$' or username in('meow','tira') then raise exception 'Choose an available handle; meow and tira are reserved'; end if;
  end if;
  update public.onestep_beta_invites set used_by=new.id where code_hash=invite.code_hash;
  insert into public.onestep_enrollments values(new.id,invite.kind,lower(trim(new.email)),username);
  -- Enrollment secrets never persist in the user's editable metadata.
  new.raw_user_meta_data:=coalesce(new.raw_user_meta_data,'{}'::jsonb)-'beta_key'-'is_admin'-'role';
  return new;
end $$;
create trigger onestep_enroll_before_auth_insert before insert on auth.users for each row execute function public.onestep_enroll_before_auth_insert();
create function public.onestep_enroll_after_auth_insert() returns trigger
language plpgsql security definer set search_path='' as $$
declare enrollment public.onestep_enrollments%rowtype; begin
  select * into enrollment from public.onestep_enrollments where user_id=new.id;
  if not found then raise exception 'Enrollment authorization missing'; end if;
  insert into public.onestep_account_kinds values(new.id,enrollment.kind);
  insert into public.onestep_profiles(user_id,display_name,handle,leaderboard_opt_in)
    values(new.id,case when enrollment.kind='kids' then enrollment.email else enrollment.handle end,enrollment.handle,false);
  if enrollment.kind='owner' then insert into public.onestep_admins values(new.id); end if;
  delete from public.onestep_enrollments where user_id=new.id;
  return new;
end $$;
create trigger onestep_enroll_after_auth_insert after insert on auth.users for each row execute function public.onestep_enroll_after_auth_insert();
revoke all on function public.onestep_enroll_before_auth_insert(),public.onestep_enroll_after_auth_insert() from public,anon,authenticated;

create function public.onestep_is_admin() returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.onestep_admins where user_id=auth.uid())
$$;
create function public.onestep_issue_beta_key(account_kind text, bound_email text default null) returns text
language plpgsql security definer set search_path='' as $$
declare secret text; begin
  if not public.onestep_is_admin() then raise exception 'Admin required' using errcode='42501'; end if;
  if account_kind not in('normal','parent','kids') then raise exception 'Invalid account kind'; end if;
  secret:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
  insert into public.onestep_beta_invites(code_hash,kind,email,issued_by)
    values(encode(sha256(convert_to(secret,'UTF8')),'hex'),account_kind,nullif(lower(trim(bound_email)),''),auth.uid());
  return secret;
end $$;
create function public.onestep_update_profile(profile_name text, profile_handle text, opt_in boolean) returns void
language plpgsql security definer set search_path='' as $$
declare kind text; wanted_handle text:=lower(trim(profile_handle)); begin
  select k.kind into kind from public.onestep_account_kinds k where user_id=auth.uid();
  if kind is null or kind='kids' then raise exception 'Child profiles cannot have public names or rankings' using errcode='42501'; end if;
  if (wanted_handle in('meow','tira') or lower(trim(profile_name)) in('meow','tira')) and kind<>'owner' then raise exception 'Reserved name or handle'; end if;
  update public.onestep_profiles set display_name=trim(profile_name),handle=wanted_handle,leaderboard_opt_in=coalesce(opt_in,false) where user_id=auth.uid();
end $$;
create or replace view public.onestep_leaderboard with(security_barrier=true) as
  select p.display_name,coalesce(sum(l.delta),0)::bigint as points,p.handle
  from public.onestep_profiles p left join public.onestep_points_ledger l on l.user_id=p.user_id
  where p.leaderboard_opt_in and not exists(select 1 from public.onestep_account_kinds k where k.user_id=p.user_id and k.kind='kids')
    and not exists(select 1 from public.onestep_children c where c.child_id=p.user_id)
  group by p.user_id,p.display_name,p.handle order by points desc,p.display_name asc limit 100;

create or replace function public.onestep_create_family(family_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare family uuid; begin
  if not exists(select 1 from public.onestep_account_kinds where user_id=auth.uid() and kind in('parent','owner')) then raise exception 'Parent account required' using errcode='42501'; end if;
  insert into public.onestep_families(parent_id,name) values(auth.uid(),trim(family_name)) returning id into family;
  return family;
end $$;
create function public.onestep_admin_users() returns table(id uuid,email text,kind text,points bigint)
language plpgsql stable security definer set search_path='' as $$
begin
  if not public.onestep_is_admin() then raise exception 'Admin required' using errcode='42501'; end if;
  return query select u.id,u.email::text,k.kind,coalesce(sum(l.delta),0)::bigint
    from auth.users u left join public.onestep_account_kinds k on k.user_id=u.id left join public.onestep_points_ledger l on l.user_id=u.id
    group by u.id,u.email,k.kind order by u.created_at desc limit 100;
end $$;
revoke all on function public.onestep_is_admin(),public.onestep_issue_beta_key(text,text),public.onestep_update_profile(text,text,boolean),public.onestep_admin_users() from public,anon,authenticated;
grant execute on function public.onestep_is_admin(),public.onestep_issue_beta_key(text,text),public.onestep_update_profile(text,text,boolean),public.onestep_admin_users() to authenticated;
commit;
