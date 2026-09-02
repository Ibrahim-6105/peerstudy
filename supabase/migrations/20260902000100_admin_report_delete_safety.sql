-- Make Admin report removal safe when another action already hid the target.
--
-- Report rows intentionally outlive moderated content.  A moderation retry must
-- therefore be able to finish the pending report even when its Post or Comment
-- is already removed (or an older/imported database has lost the target row).

begin;

create or replace function public.admin_resolve_report(
  p_report_id uuid,
  p_action text,
  p_resolution_note text
)
returns public.reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_note text := btrim(coalesce(p_resolution_note, ''));
  v_report public.reports;
  v_post_id uuid;
  v_target_author uuid;
  v_target_role text;
  v_target_status text;
  v_target_exists boolean := false;
  v_target_already_removed boolean := false;
  v_new_status text;
begin
  if v_admin_id is null or not public.is_admin() then
    raise exception 'An active Admin account is required' using errcode = '42501';
  end if;
  if p_report_id is null or v_action not in ('dismiss', 'remove', 'restrict') then
    raise exception 'A valid report id and action are required' using errcode = '22023';
  end if;
  if char_length(v_note) not between 5 and 1000 then
    raise exception 'Resolution note must contain 5-1000 characters' using errcode = '22023';
  end if;

  -- Lock the report first so two Admin devices cannot apply competing actions.
  select * into v_report
  from public.reports
  where id = p_report_id
  for update;

  if v_report.id is null then
    raise exception 'Report was not found' using errcode = 'P0002';
  end if;

  -- A lost response followed by the same removal retry is a successful no-op.
  -- Other action changes remain conflicts because they alter the audit outcome.
  if v_report.status <> 'pending' then
    if v_action = 'remove' and v_report.status = 'content_removed' then
      return v_report;
    end if;
    raise exception 'Report was already resolved' using errcode = '55000';
  end if;

  -- Lock an existing target while deciding its state.  Missing targets are
  -- tolerated for dismiss/remove, but never for restricting an unknown author.
  if v_report.post_id is not null then
    v_post_id := v_report.post_id;
    select p.author_id, p.status
    into v_target_author, v_target_status
    from public.community_posts p
    where p.id = v_report.post_id
    for update;
    v_target_exists := found;
  else
    select cc.post_id, cc.author_id, cc.status
    into v_post_id, v_target_author, v_target_status
    from public.community_comments cc
    where cc.id = v_report.comment_id
    for update;
    v_target_exists := found;
  end if;

  -- Every report affecting the same Post takes the same parent-row lock before
  -- changing report status.  This serializes the final is_reported recompute
  -- when two Admins resolve reports on different Comments at the same time.
  -- A direct Post target is already locked above; taking its lock again in the
  -- same transaction is harmless and keeps one explicit ordering rule:
  -- report -> exact target -> parent Post.
  if v_post_id is not null then
    perform 1
    from public.community_posts p
    where p.id = v_post_id
    for update;
  end if;

  if v_action = 'dismiss' then
    v_new_status := 'dismissed';
  elsif v_action = 'remove' then
    -- Soft deletion preserves the report foreign key and audit history.  Zero
    -- target rows or an already-removed row are both valid idempotent outcomes.
    if v_target_exists and v_target_status = 'active' then
      if v_report.post_id is not null then
        update public.community_posts
        set status = 'removed',
            version = version + 1,
            removal_reason = left(v_note, 500),
            removed_at = now(),
            removed_by = v_admin_id
        where id = v_report.post_id;
      else
        update public.community_comments
        set status = 'removed',
            version = version + 1,
            removal_reason = left(v_note, 500),
            removed_at = now(),
            removed_by = v_admin_id
        where id = v_report.comment_id;
      end if;
    elsif v_target_exists and v_target_status = 'removed' then
      v_target_already_removed := true;
    elsif v_target_exists then
      raise exception 'Report target has an invalid status' using errcode = '55000';
    end if;
    v_new_status := 'content_removed';
  else
    if not v_target_exists or v_target_author is null then
      raise exception 'Report target no longer exists' using errcode = 'P0002';
    end if;

    select p.role into v_target_role
    from public.profiles p
    where p.id = v_target_author
    for update;

    if not found then
      raise exception 'Report target author no longer exists' using errcode = 'P0002';
    end if;
    if v_target_author = v_admin_id or v_target_role is distinct from 'student' then
      raise exception 'Admin accounts cannot be restricted through a content report'
        using errcode = '42501';
    end if;

    update public.profiles
    set status = 'restricted',
        restricted_at = now(),
        restricted_by = v_admin_id,
        restriction_reason = left(v_note, 500)
    where id = v_target_author;
    v_new_status := 'account_restricted';
  end if;

  -- Resolving the report and changing its target remain one transaction.
  update public.reports
  set status = v_new_status,
      resolved_at = now(),
      resolved_by = v_admin_id,
      resolution_note = v_note
  where id = p_report_id
  returning * into v_report;

  -- The parent Post may itself be missing in a legacy/imported database.  An
  -- update of zero rows is safe; an existing Post keeps its exact pending flag.
  update public.community_posts p
  set is_reported = exists (
    select 1
    from public.reports r
    where r.status = 'pending'
      and (
        r.post_id = p.id
        or r.comment_id in (
          select cc.id
          from public.community_comments cc
          where cc.post_id = p.id
        )
      )
  )
  where p.id = v_post_id;

  insert into public.admin_audit_log (
    actor_id, action, entity_type, entity_id, details
  ) values (
    v_admin_id,
    'resolve_report_' || v_action,
    'report',
    p_report_id,
    jsonb_build_object(
      'target_type', v_report.target_type,
      'target_id', v_report.target_id,
      'target_existed', v_target_exists,
      'target_already_removed', v_target_already_removed
    )
  );

  return v_report;
end;
$$;

-- CREATE OR REPLACE normally retains grants; repeat the narrow privilege list
-- so a restored database cannot inherit an unsafe PUBLIC execute permission.
revoke execute on function public.admin_resolve_report(uuid, text, text)
from public, anon, authenticated;
grant execute on function public.admin_resolve_report(uuid, text, text)
to authenticated;

commit;
