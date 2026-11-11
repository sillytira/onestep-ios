\set ON_ERROR_STOP on
\ir identity-test.sql
\ir 004_parent_controls.sql
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select public.onestep_create_family('Owner test family');
select public.onestep_create_family_invite() as family_code \gset
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
select public.onestep_accept_family_invite(:'family_code','This nickname must be ignored');
do $$ begin
  if (select nickname from public.onestep_children where child_id=auth.uid())<>'kid@example.invalid' then raise exception 'Child is not displayed by email'; end if;
  begin
    perform public.onestep_unlink_child(auth.uid());
    raise exception 'Child unlinked itself' using errcode='P0002';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select public.onestep_set_parent_pin('55555555-5555-4555-8555-555555555555',jsonb_build_object('algorithm','pbkdf2-sha256','iterations',120000,'salt',encode(decode(repeat('00',16),'hex'),'base64'),'hash',encode(decode(repeat('00',32),'hex'),'base64')));
select public.onestep_unlink_child('55555555-5555-4555-8555-555555555555');
do $$ begin
  if exists(select 1 from public.onestep_children where child_id='55555555-5555-4555-8555-555555555555' and active) then raise exception 'Parent unlink failed'; end if;
end $$;
reset role;
select 'PASS: parent-only unlink and verifier setup, email-only child display, and retained linked history';
