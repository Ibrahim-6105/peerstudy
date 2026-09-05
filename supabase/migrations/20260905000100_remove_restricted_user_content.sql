-- Remove a Student's Community content whenever an Admin restricts the account.
--
-- PeerStudy uses audited soft deletion for Posts, Comments, and Attachments so
-- reports remain reviewable.  The removal is part of the same transaction as
-- the profile restriction: either the account and all content are hidden, or
-- neither change is committed.

begin;

create or replace function public.remove_restricted_student_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Run on every explicit restricted-status write.  Repeating a restriction
  -- safely sweeps any legacy active rows while already removed rows are kept.
  if new.role = 'student' and new.status = 'restricted' then
    -- Remove Comments first so the existing count trigger keeps active parent
    -- Post counts correct.  Its attachment trigger hides attached files too.
    update public.community_comments
    set status = 'removed',
        version = version + 1,
        removal_reason = 'Author account was restricted',
        removed_at = now(),
        removed_by = new.restricted_by
    where author_id = new.id
      and status = 'active';

    -- Removing a Post also invokes the existing attachment trigger, which
    -- hides files attached directly to the Post and anywhere in its thread.
    update public.community_posts
    set status = 'removed',
        version = version + 1,
        removal_reason = 'Author account was restricted',
        removed_at = now(),
        removed_by = new.restricted_by
    where author_id = new.id
      and status = 'active';
  end if;

  return new;
end;
$$;

revoke execute on function public.remove_restricted_student_content()
from public, anon, authenticated;

drop trigger if exists profiles_remove_restricted_content on public.profiles;
create trigger profiles_remove_restricted_content
after update of status on public.profiles
for each row execute function public.remove_restricted_student_content();

-- Bring accounts restricted before this migration under the same invariant.
-- These updates intentionally use the same canonical soft-deletion fields and
-- therefore also activate Comment-count and Attachment-hiding triggers.
update public.community_comments cc
set status = 'removed',
    version = cc.version + 1,
    removal_reason = 'Author account was restricted',
    removed_at = now(),
    removed_by = p.restricted_by
from public.profiles p
where p.id = cc.author_id
  and p.role = 'student'
  and p.status = 'restricted'
  and cc.status = 'active';

update public.community_posts cp
set status = 'removed',
    version = cp.version + 1,
    removal_reason = 'Author account was restricted',
    removed_at = now(),
    removed_by = p.restricted_by
from public.profiles p
where p.id = cp.author_id
  and p.role = 'student'
  and p.status = 'restricted'
  and cp.status = 'active';

commit;
