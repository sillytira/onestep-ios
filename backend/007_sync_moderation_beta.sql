-- Apply once after 006. No privileged key belongs in a client.
begin;
create table public.onestep_sync_snapshots (
 user_id uuid primary key references auth.users(id) on delete cascade,
 revision bigint not null check(revision>0), envelope text not null check(octet_length(envelope)<=12582912),updated_at timestamptz not null default now()
);
create table public.onestep_moderator_permissions (
 user_id uuid not null references auth.users(id) on delete cascade,
 permission text not null check(permission in('accounts.read','accounts.ban','points.adjust','invites.issue')),
 granted_by uuid not null references auth.users(id),primary key(user_id,permission)
);
create table public.onestep_account_controls (
 user_id uuid primary key references auth.users(id),banned_until timestamptz,reason text not null,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
create table public.onestep_moderation_audit (
 id uuid primary key default gen_random_uuid(),actor uuid not null,target uuid,action text not null,details jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()
);
alter table public.onestep_sync_snapshots enable row level security;
alter table public.onestep_moderator_permissions enable row level security;
alter table public.onestep_account_controls enable row level security;
alter table public.onestep_moderation_audit enable row level security;
revoke all on public.onestep_sync_snapshots,public.onestep_moderator_permissions,public.onestep_account_controls,public.onestep_moderation_audit from public,anon,authenticated;
-- Snapshot access is through bounded revision-checked RPCs only.
create function public.onestep_is_owner() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.onestep_account_kinds k join public.onestep_admins a on a.user_id=k.user_id where k.user_id=auth.uid() and k.kind='owner')
$$;
create function public.onestep_access_allowed(actor uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.onestep_account_controls c where c.user_id=actor and c.banned_until>now())
$$;
create function public.onestep_assert_active() returns void language plpgsql stable security definer set search_path='' as $$ begin
 if not public.onestep_access_allowed(auth.uid()) then raise exception 'This account is suspended from online OneStep services. Contact the owner.' using errcode='42501';end if;
end $$;
create function public.onestep_has_permission(capability text) returns boolean language sql stable security definer set search_path='' as $$
 select public.onestep_is_owner() or exists(select 1 from public.onestep_moderator_permissions p where p.user_id=auth.uid() and p.permission=capability)
$$;
create function public.onestep_sync_read() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare row public.onestep_sync_snapshots%rowtype;begin
 perform public.onestep_assert_active();
 if not exists(select 1 from public.onestep_account_kinds where user_id=auth.uid()) then raise exception 'Enrolled account required' using errcode='42501';end if;
 select * into row from public.onestep_sync_snapshots where user_id=auth.uid();
 if not found then return jsonb_build_object('revision',0,'envelope',null);end if;
 return jsonb_build_object('revision',row.revision,'envelope',row.envelope,'updated_at',row.updated_at);
end $$;
create function public.onestep_sync_publish(expected_revision bigint,payload text) returns jsonb language plpgsql security definer set search_path='' as $$
declare current_revision bigint;begin
 perform public.onestep_assert_active();
 if not exists(select 1 from public.onestep_account_kinds where user_id=auth.uid()) then raise exception 'Enrolled account required' using errcode='42501';end if;
 if expected_revision is null or expected_revision<0 or payload is null or octet_length(payload)>12582912 or (payload::jsonb->>'format') is distinct from 'OneStepEncrypted' then raise exception 'Invalid encrypted snapshot';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,71));
 select revision into current_revision from public.onestep_sync_snapshots where user_id=auth.uid();current_revision:=coalesce(current_revision,0);
 if current_revision<>expected_revision then return jsonb_build_object('status','conflict','revision',current_revision);end if;
 insert into public.onestep_sync_snapshots(user_id,revision,envelope) values(auth.uid(),current_revision+1,payload)
 on conflict(user_id) do update set revision=excluded.revision,envelope=excluded.envelope,updated_at=now();
 return jsonb_build_object('status','saved','revision',current_revision+1);
end $$;

-- Immutable earning cohorts keep beta history separate from any future production rankings.
alter table public.onestep_profiles add column ranking_cohort text not null default 'beta-v1' check(ranking_cohort in('beta-v1','production-v1'));
alter table public.onestep_personal_tasks add column cohort text not null default 'beta-v1';
alter table public.onestep_xp_events add column cohort text not null default 'beta-v1';
create function public.onestep_stamp_cohort() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if TG_OP='UPDATE' then if new.cohort<>old.cohort then raise exception 'Earning cohort is immutable';end if;return new;end if;
 select ranking_cohort into new.cohort from public.onestep_profiles where user_id=new.user_id;return new;
end $$;
create trigger personal_cohort before insert or update on public.onestep_personal_tasks for each row execute function public.onestep_stamp_cohort();
create trigger xp_cohort before insert or update on public.onestep_xp_events for each row execute function public.onestep_stamp_cohort();
create or replace function public.onestep_xp_rankings() returns table(display_name text,handle text,earned_xp bigint)
language plpgsql stable security definer set search_path='' as $$ begin
 if auth.uid() is null then raise exception 'Sign in first' using errcode='42501';end if;
 return query select p.display_name,p.handle,coalesce(sum(x.awarded),0)::bigint from public.onestep_profiles p
 left join public.onestep_xp_events x on x.user_id=p.user_id and x.cohort=p.ranking_cohort and x.created_at>=date_trunc('week',now() at time zone 'UTC') at time zone 'UTC'
 where p.xp_leaderboard_opt_in and p.ranking_cohort=(select ranking_cohort from public.onestep_profiles where user_id=auth.uid())
 and exists(select 1 from public.onestep_account_kinds k where k.user_id=p.user_id and k.kind in('normal','parent','owner'))
 and not exists(select 1 from public.onestep_children c where c.child_id=p.user_id) and public.onestep_access_allowed(p.user_id)
 group by p.user_id,p.display_name,p.handle order by sum(x.awarded) desc nulls last,p.handle limit 100;
end $$;
create or replace function public.onestep_rankings(metric text default 'tasks') returns table(display_name text,handle text,completed_tasks bigint,earned_points bigint)
language plpgsql stable security definer set search_path='' as $$ begin
 if auth.uid() is null then raise exception 'Sign in first' using errcode='42501';end if;
 if metric not in('tasks','points') then raise exception 'Invalid ranking metric';end if;
 return query select p.display_name,p.handle,count(t.id)::bigint,coalesce(sum(t.awarded),0)::bigint from public.onestep_profiles p
 left join public.onestep_personal_tasks t on t.user_id=p.user_id and t.cohort=p.ranking_cohort and t.counted and t.completed_at>=date_trunc('week',now() at time zone 'UTC') at time zone 'UTC'
 where p.leaderboard_opt_in and p.ranking_cohort=(select ranking_cohort from public.onestep_profiles where user_id=auth.uid())
 and exists(select 1 from public.onestep_account_kinds k where k.user_id=p.user_id and k.kind in('normal','parent','owner'))
 and not exists(select 1 from public.onestep_children c where c.child_id=p.user_id) and public.onestep_access_allowed(p.user_id)
 group by p.user_id,p.display_name,p.handle order by case when metric='tasks' then count(t.id)::bigint else coalesce(sum(t.awarded),0)::bigint end desc,p.handle limit 100;
end $$;
create or replace view public.onestep_leaderboard with(security_barrier=true) as
 select p.display_name,coalesce(sum(t.awarded),0)::bigint as points,p.handle from public.onestep_profiles p
 left join public.onestep_personal_tasks t on t.user_id=p.user_id and t.cohort=p.ranking_cohort and t.counted and t.completed_at>=date_trunc('week',now() at time zone 'UTC') at time zone 'UTC'
 where p.leaderboard_opt_in and p.ranking_cohort=(select ranking_cohort from public.onestep_profiles where user_id=auth.uid())
 and exists(select 1 from public.onestep_account_kinds k where k.user_id=p.user_id and k.kind in('normal','parent','owner'))
 and not exists(select 1 from public.onestep_children c where c.child_id=p.user_id) and public.onestep_access_allowed(p.user_id) and public.onestep_access_allowed(auth.uid())
 group by p.user_id,p.display_name,p.handle order by points desc,p.handle limit 100;

create function public.onestep_moderation_status() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('owner',public.onestep_is_owner(),'permissions',coalesce((select jsonb_agg(permission order by permission) from public.onestep_moderator_permissions where user_id=auth.uid()),'[]'::jsonb),'cohort',(select ranking_cohort from public.onestep_profiles where user_id=auth.uid()))
$$;
create function public.onestep_grant_moderator(target uuid,permissions text[]) returns void language plpgsql security definer set search_path='' as $$ begin
 if not public.onestep_is_owner() then raise exception 'Owner required' using errcode='42501';end if;
 if target is null or permissions is null or cardinality(permissions)>4 or not permissions<@array['accounts.read','accounts.ban','points.adjust','invites.issue'] or not exists(select 1 from public.onestep_account_kinds where user_id=target and kind in('normal','parent')) then raise exception 'Choose an enrolled adult account and known permissions';end if;
 delete from public.onestep_moderator_permissions where user_id=target;
 insert into public.onestep_moderator_permissions select target,p,auth.uid() from (select distinct unnest(permissions) as p) x;
 insert into public.onestep_moderation_audit(actor,target,action,details) values(auth.uid(),target,'permissions',jsonb_build_object('permissions',permissions));
end $$;
create function public.onestep_moderation_users() returns jsonb language plpgsql stable security definer set search_path='' as $$ begin
 if not public.onestep_has_permission('accounts.read') then raise exception 'Account read permission required' using errcode='42501';end if;
 return coalesce((select jsonb_agg(x) from (select p.user_id as id,p.display_name as name,k.kind,
 case when public.onestep_is_owner() then u.email else null end as email,
 coalesce(c.banned_until>now(),false) as banned,
 case when public.onestep_is_owner() then (select coalesce(jsonb_agg(permission),'[]'::jsonb) from public.onestep_moderator_permissions where user_id=p.user_id) else '[]'::jsonb end as permissions
 from public.onestep_profiles p join public.onestep_account_kinds k on k.user_id=p.user_id join auth.users u on u.id=p.user_id left join public.onestep_account_controls c on c.user_id=p.user_id
 where public.onestep_is_owner() or k.kind<>'kids' order by p.display_name,p.user_id limit 200) x),'[]'::jsonb);
end $$;
create function public.onestep_set_ban(target uuid,days integer,explanation text) returns void language plpgsql security definer set search_path='' as $$ begin
 if not public.onestep_has_permission('accounts.ban') then raise exception 'Ban permission required' using errcode='42501';end if;
 if target is null or target=auth.uid() or days is null or days not between 0 and 3650 or length(trim(explanation)) not between 3 and 240 then raise exception 'Choose a different account, 0–3650 days, and a reason';end if;
 if not exists(select 1 from public.onestep_account_kinds where user_id=target and kind<>'owner') or exists(select 1 from public.onestep_admins where user_id=target) then raise exception 'Owner/admin accounts cannot be suspended here' using errcode='42501';end if;
 insert into public.onestep_account_controls(user_id,banned_until,reason,updated_by) values(target,now()+make_interval(days=>days),trim(explanation),auth.uid())
 on conflict(user_id) do update set banned_until=excluded.banned_until,reason=excluded.reason,updated_by=excluded.updated_by,updated_at=now();
 insert into public.onestep_moderation_audit(actor,target,action,details) values(auth.uid(),target,case when days=0 then 'unban' else 'ban' end,jsonb_build_object('days',days,'reason',trim(explanation)));
end $$;
create function public.onestep_moderation_audit_read() returns jsonb language plpgsql stable security definer set search_path='' as $$ begin
 if not public.onestep_is_owner() then raise exception 'Owner required' using errcode='42501';end if;
 return coalesce((select jsonb_agg(x) from (select actor,target,action,details,created_at from public.onestep_moderation_audit order by created_at desc,id limit 200) x),'[]'::jsonb);
end $$;
create function public.onestep_moderator_adjust(target uuid,amount integer,explanation text,event uuid) returns bigint language plpgsql security definer set search_path='' as $$
declare balance bigint;previous public.onestep_points_ledger%rowtype;begin
 if not public.onestep_has_permission('points.adjust') then raise exception 'Points permission required' using errcode='42501';end if;
 if target is null or event is null or amount is null or amount=0 or amount not between -1000 and 1000 or length(trim(explanation)) not between 3 and 160 then raise exception 'Invalid adjustment';end if;
 if not public.onestep_is_owner() and exists(select 1 from public.onestep_admins where user_id=target) then raise exception 'Moderators cannot change owner balances' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(target::text,0));
 select * into previous from public.onestep_points_ledger where event_id=event;
 if found then if previous.user_id<>target or previous.delta<>amount or previous.actor_id<>auth.uid() or previous.reason<>left('Moderator adjustment: '||trim(explanation),160) then raise exception 'Adjustment identifier already used';end if;
 else
 select coalesce(sum(delta),0) into balance from public.onestep_points_ledger where user_id=target;
 if balance+amount<0 then raise exception 'Insufficient points';end if;
 insert into public.onestep_points_ledger(event_id,user_id,delta,reason,actor_id) values(event,target,amount,left('Moderator adjustment: '||trim(explanation),160),auth.uid());
 insert into public.onestep_moderation_audit(actor,target,action,details) values(auth.uid(),target,'points',jsonb_build_object('amount',amount,'event',event));
 end if;
 return (select coalesce(sum(delta),0) from public.onestep_points_ledger where user_id=target);
end $$;
create function public.onestep_moderator_invite(account_kind text,bound_email text default null) returns text language plpgsql security definer set search_path='' as $$
declare secret text;begin
 if not public.onestep_has_permission('invites.issue') then raise exception 'Invitation permission required' using errcode='42501';end if;
 if account_kind not in('normal','parent','kids') then raise exception 'Invalid account kind';end if;
 secret:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into public.onestep_beta_invites(code_hash,kind,email,issued_by) values(encode(sha256(convert_to(secret,'UTF8')),'hex'),account_kind,nullif(lower(trim(bound_email)),''),auth.uid());
 insert into public.onestep_moderation_audit(actor,action,details) values(auth.uid(),'invite',jsonb_build_object('kind',account_kind));return secret;
end $$;

-- Every existing/new client RPC gets a non-bypassable suspension guard. Private
-- implementations retain their original checks but cannot be called by clients.
do $$ declare f record;impl text;arglist text;body text;begin
 for f in select p.*,pg_get_function_arguments(p.oid) as arguments,pg_get_function_identity_arguments(p.oid) as identity,pg_get_function_result(p.oid) as result
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname like 'onestep_%' and p.prorettype<>'trigger'::regtype
 and p.proname not in('onestep_assert_active','onestep_access_allowed','onestep_is_owner','onestep_has_permission')
 and p.proname not like 'onestep_v7_%'
 loop
 impl:='onestep_v7_'||substr(f.proname,9);
 select coalesce(string_agg(format('%I',f.proargnames[i]),',' order by i),'') into arglist from generate_series(1,f.pronargs) i;
 execute format('alter function public.%I(%s) rename to %I',f.proname,f.identity,impl);
 execute format('revoke all on function public.%I(%s) from public,anon,authenticated',impl,f.identity);
 body:='begin perform public.onestep_assert_active(); ';
 if f.proretset then body:=body||format('return query select * from public.%I(%s);',impl,arglist);
 elsif f.prorettype='void'::regtype then body:=body||format('perform public.%I(%s); return;',impl,arglist);
 else body:=body||format('return public.%I(%s);',impl,arglist);end if;
    body:=body||' end;';
 execute format('create function public.%I(%s) returns %s language plpgsql security definer set search_path='''' as %L',f.proname,f.arguments,f.result,body);
 execute format('revoke all on function public.%I(%s) from public,anon,authenticated',f.proname,f.identity);
 execute format('grant execute on function public.%I(%s) to authenticated',f.proname,f.identity);
 end loop;
end $$;
revoke all on function public.onestep_assert_active(),public.onestep_is_owner(),public.onestep_access_allowed(uuid),public.onestep_has_permission(text),public.onestep_stamp_cohort() from public,anon,authenticated;
grant execute on function public.onestep_is_owner(),public.onestep_access_allowed(uuid),public.onestep_has_permission(text) to authenticated;
-- Restrictive policies also protect direct table requests, not just RPCs.
do $$ declare t record;begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'onestep_%' loop
 execute format('create policy active_account on public.%I as restrictive for all to authenticated using(public.onestep_access_allowed(auth.uid())) with check(public.onestep_access_allowed(auth.uid()))',t.tablename);
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
