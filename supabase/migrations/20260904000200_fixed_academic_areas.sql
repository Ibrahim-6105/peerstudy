-- Keep PeerStudy's top-level academic catalog fixed for the current release.
--
-- Students and Admins may still read Engineering and IT. Department, Subject,
-- and Material management remains unchanged. Removing both policies and table
-- privileges ensures a modified public client cannot restore hidden Area CRUD.

begin;

drop policy if exists academic_areas_admin_insert on public.academic_areas;
drop policy if exists academic_areas_admin_update on public.academic_areas;
drop policy if exists academic_areas_admin_delete on public.academic_areas;

revoke insert, update, delete on table public.academic_areas
from anon, authenticated;

commit;
