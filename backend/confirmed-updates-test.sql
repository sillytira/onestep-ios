\set ON_ERROR_STOP on
\ir economy-xp-test.sql
\ir 007_sync_moderation_beta.sql
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
set role authenticated;
do $$ declare r jsonb;begin
 r:=public.onestep_sync_publish(0,'{"format":"OneStepEncrypted","version":1}');
 if r->>'status'<>'saved' then raise exception 'Initial encrypted sync failed';end if;
 r:=public.onestep_sync_publish(0,'{"format":"OneStepEncrypted","version":1,"changed":true}');
 if r->>'status'<>'conflict' then raise exception 'Stale revision overwrote cloud';end if;
 if public.onestep_sync_read()->>'revision'<>'1' then raise exception 'Wrong cloud revision';end if;
 begin perform public.onestep_grant_moderator(auth.uid(),array['accounts.ban']);raise exception 'Self promotion accepted' using errcode='P0002';exception when insufficient_privilege then null;end;
 begin perform public.onestep_moderation_users();raise exception 'Member read moderation data' using errcode='P0002';exception when insufficient_privilege then null;end;
 begin perform public.onestep_v7_my_balance();raise exception 'Private implementation exposed' using errcode='P0002';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
do $$ begin
 if public.onestep_sync_read()->>'revision'<>'0' then raise exception 'Owner read another planner snapshot';end if;
 perform public.onestep_grant_moderator('66666666-6666-4666-8666-666666666666',array['accounts.read','accounts.ban']);
end $$;
select public.onestep_moderator_invite('normal','moderation@example.invalid') as mod_code \gset
reset role;
insert into auth.users(id,email,raw_user_meta_data) values('88888888-8888-4888-8888-888888888888','moderation@example.invalid',jsonb_build_object('beta_key',:'mod_code','username','modtarget'));
set role authenticated;
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
do $$ declare users jsonb;begin
 users:=public.onestep_moderation_users();
 if exists(select 1 from jsonb_array_elements(users) x where x->>'kind'='kids' or x->>'email' is not null) then raise exception 'Moderator leaked child/email data';end if;
 begin perform public.onestep_set_ban('44444444-4444-4444-8444-444444444444',7,'Forged owner suspension');raise exception 'Owner suspension accepted' using errcode='P0002';exception when insufficient_privilege then null;end;
 begin perform public.onestep_moderator_adjust(auth.uid(),10,'Forged adjustment',gen_random_uuid());raise exception 'Missing capability bypassed' using errcode='P0002';exception when insufficient_privilege then null;end;
 perform public.onestep_set_ban('88888888-8888-4888-8888-888888888888',7,'Synthetic moderation test');
end $$;
select set_config('request.jwt.claim.sub','88888888-8888-4888-8888-888888888888',false);
do $$ begin
 begin perform public.onestep_my_balance();raise exception 'Suspended RPC was allowed' using errcode='P0002';exception when insufficient_privilege then null;end;
 begin perform public.onestep_sync_read();raise exception 'Suspended cloud read allowed' using errcode='P0002';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.onestep_profiles) then raise exception 'Suspended direct table read allowed';end if;
end $$;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select public.onestep_set_ban('88888888-8888-4888-8888-888888888888',0,'Synthetic appeal accepted');
select public.onestep_grant_moderator('66666666-6666-4666-8666-666666666666',array['points.adjust','invites.issue']);
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
do $$ declare event uuid:=gen_random_uuid();balance bigint;begin
 balance:=public.onestep_moderator_adjust(auth.uid(),10,'Synthetic moderator credit',event);
 if public.onestep_moderator_adjust(auth.uid(),10,'Synthetic moderator credit',event)<>balance then raise exception 'Adjustment replay credited twice';end if;
 begin perform public.onestep_moderation_users();raise exception 'Revoked read retained' using errcode='P0002';exception when insufficient_privilege then null;end;
 begin perform public.onestep_moderation_audit_read();raise exception 'Moderator read owner audit' using errcode='P0002';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select public.onestep_grant_moderator('66666666-6666-4666-8666-666666666666','{}'::text[]);
do $$ begin if jsonb_array_length(public.onestep_moderation_audit_read())<5 then raise exception 'Missing moderation audit';end if;end $$;
reset role;
update public.onestep_profiles set ranking_cohort='production-v1',xp_leaderboard_opt_in=true where user_id='66666666-6666-4666-8666-666666666666';
update public.onestep_xp_events set created_at=now()-interval '1 day' where user_id='66666666-6666-4666-8666-666666666666';
set role authenticated;
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
do $$ declare score bigint;begin
 select earned_xp into score from public.onestep_xp_rankings() where handle='member';
 if score<>0 then raise exception 'Beta XP leaked into production ranking';end if;
 perform public.onestep_claim_xp('task.production-fixture','task');
 select earned_xp into score from public.onestep_xp_rankings() where handle='member';
 if score<>10 then raise exception 'New production XP did not use current cohort';end if;
end $$;
set role anon;
do $$ begin
 begin perform public.onestep_sync_read();raise exception 'Anonymous cloud read' using errcode='P0002';exception when insufficient_privilege then null;end;
 begin perform public.onestep_moderation_status();raise exception 'Anonymous moderation status' using errcode='P0002';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: revision-safe encrypted sync, owner-only delegation, granular moderation, bans on old RPCs/direct reads, immutable beta/production cohorts and anonymous denial';
