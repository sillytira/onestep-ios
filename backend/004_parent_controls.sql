begin;
alter table public.onestep_children add column active boolean not null default true;
alter table public.onestep_children add column offline_pin_verifier jsonb;

create function public.onestep_set_parent_pin(child uuid,verifier jsonb) returns void
language plpgsql security definer set search_path='' as $$
begin
  if verifier is null or verifier->>'algorithm' is distinct from 'pbkdf2-sha256' or (verifier->>'iterations')::integer is distinct from 120000
    or coalesce(length(decode(verifier->>'salt','base64')),0)<>16 or coalesce(length(decode(verifier->>'hash','base64')),0)<>32 then raise exception 'Invalid verifier'; end if;
  update public.onestep_children c set offline_pin_verifier=verifier
    from public.onestep_families f where c.child_id=child and c.family_id=f.id and c.active and f.parent_id=auth.uid();
  if not found then raise exception 'Linked parent authorization required' using errcode='42501'; end if;
end $$;
create function public.onestep_unlink_child(child uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  update public.onestep_children c set active=false,offline_pin_verifier=null
    from public.onestep_families f where c.child_id=child and c.family_id=f.id and f.parent_id=auth.uid();
  if not found then raise exception 'Linked parent authorization required' using errcode='42501'; end if;
end $$;
create or replace function public.onestep_accept_family_invite(invite_code text,child_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare family uuid; actor uuid:=auth.uid(); display_email text; begin
  if actor is null or not exists(select 1 from public.onestep_account_kinds where user_id=actor and kind='kids') then raise exception 'Kids account required' using errcode='42501'; end if;
  if length(invite_code)<>64 then raise exception 'Invalid or expired invitation'; end if;
  if exists(select 1 from public.onestep_children where child_id=actor and active) then raise exception 'Parent must unlink the current family first' using errcode='42501'; end if;
  delete from public.onestep_family_invites where code_hash=encode(sha256(convert_to(invite_code,'UTF8')),'hex') and expires_at>now() returning family_id into family;
  if family is null then raise exception 'Invalid or expired invitation'; end if;
  select email into display_email from auth.users where id=actor;
  insert into public.onestep_children(child_id,family_id,nickname) values(actor,family,display_email)
    on conflict(child_id) do update set family_id=excluded.family_id,nickname=excluded.nickname,active=true,offline_pin_verifier=null;
  return family;
end $$;
revoke all on function public.onestep_set_parent_pin(uuid,jsonb),public.onestep_unlink_child(uuid) from public,anon,authenticated;
grant execute on function public.onestep_set_parent_pin(uuid,jsonb),public.onestep_unlink_child(uuid) to authenticated;
commit;
