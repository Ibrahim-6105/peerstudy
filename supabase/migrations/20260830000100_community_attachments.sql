-- Add secure file attachments to Community Posts and Comments.
--
-- This is a forward-only migration.  The original corrected-master migration
-- stays unchanged so an already deployed PeerStudy database can be upgraded
-- without losing accounts, Posts, Comments, reports, or study content.

begin;

-- Attachment bytes live in a private Storage bucket.  This table stores only
-- the trusted metadata needed to authorize an upload or download.
create table public.community_attachments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.community_posts(id) on delete cascade,
  comment_id uuid references public.community_comments(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  file_name text not null,
  storage_path text not null unique,
  mime_type text not null,
  size_bytes bigint not null,
  checksum text,
  status text not null default 'uploading',
  idempotency_key uuid not null,
  removal_reason text,
  removed_at timestamptz,
  removed_by uuid references public.profiles(id) on delete set null,
  storage_deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- One Attachment belongs to one Post OR one Comment, never both/neither.
  constraint community_attachments_one_target_check check (
    (post_id is not null)::integer + (comment_id is not null)::integer = 1
  ),

  -- Keep the original display name safe and short.  The name is never used as
  -- a Storage path, which avoids path traversal and duplicate-name problems.
  constraint community_attachments_file_name_check check (
    file_name = btrim(file_name)
    and char_length(file_name) between 1 and 180
    and position('/' in file_name) = 0
    and position(E'\\' in file_name) = 0
    and file_name !~ '[[:cntrl:]]'
  ),

  -- The phone may upload only formats that PeerStudy can safely preview or
  -- hand to an installed document viewer.  Executables, HTML, and SVG are not
  -- accepted because Community files are untrusted user content.
  constraint community_attachments_mime_check check (mime_type in (
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'text/plain'
  )),

  -- An extension must agree with the declared MIME type.  Finalization also
  -- checks the MIME type recorded by Storage before making the file visible.
  constraint community_attachments_extension_check check (
    (mime_type = 'image/jpeg' and lower(file_name) ~ '[.](jpg|jpeg)$')
    or (mime_type = 'image/png' and lower(file_name) ~ '[.]png$')
    or (mime_type = 'image/webp' and lower(file_name) ~ '[.]webp$')
    or (mime_type = 'application/pdf' and lower(file_name) ~ '[.]pdf$')
    or (mime_type = 'text/plain' and lower(file_name) ~ '[.]txt$')
  ),

  -- Ten MiB keeps mobile uploads reasonable while still supporting notes,
  -- screenshots, PDFs, and plain-text notes.
  constraint community_attachments_size_check check (
    size_bytes between 1 and 10485760
  ),

  -- The server creates opaque paths in "user UUID/attachment UUID" form.  A
  -- caller cannot choose a different folder or overwrite another user's file.
  constraint community_attachments_path_check check (
    storage_path = uploaded_by::text || '/' || id::text
    and storage_path !~ '[.][.]'
  ),

  constraint community_attachments_status_check check (
    status in ('uploading', 'ready', 'removed')
  ),

  -- Only the byte-validating Edge Function supplies this SHA-256 digest.  A
  -- ready file can therefore never be produced by trusting phone metadata.
  constraint community_attachments_checksum_check check (
    checksum is null or checksum ~ '^[0-9a-f]{64}$'
  ),

  constraint community_attachments_ready_check check (
    (status = 'ready' and checksum is not null)
    or (status <> 'ready')
  ),

  -- Removal is a soft delete.  It hides access immediately while retaining a
  -- small audit record; the phone then deletes the inaccessible Storage byte.
  constraint community_attachments_removal_check check (
    (
      status = 'removed'
      and removed_at is not null
      and removal_reason is not null
      and char_length(btrim(removal_reason)) between 3 and 500
    )
    or
    (
      status <> 'removed'
      and removed_at is null
      and removal_reason is null
      and removed_by is null
    )
  ),

  constraint community_attachments_storage_deleted_check check (
    storage_deleted_at is null or status = 'removed'
  ),

  -- Retrying one phone request returns its original row instead of creating a
  -- second upload slot or a second Storage object.
  constraint community_attachments_author_request_key unique (
    uploaded_by, idempotency_key
  )
);

-- These indexes support the two feed queries and Storage authorization checks.
create index community_attachments_post_status_idx
  on public.community_attachments (post_id, status, created_at)
  where post_id is not null;

create index community_attachments_comment_status_idx
  on public.community_attachments (comment_id, status, created_at)
  where comment_id is not null;

create index community_attachments_uploader_status_idx
  on public.community_attachments (uploaded_by, status, created_at desc);

create index community_attachments_pending_cleanup_idx
  on public.community_attachments (created_at)
  where status = 'removed' and storage_deleted_at is null;

-- Reuse the corrected-master timestamp trigger for consistent update times.
create trigger community_attachments_set_updated_at
before update on public.community_attachments
for each row execute function public.set_updated_at();

-- This private helper answers whether the current signed-in user may download
-- one ready object.  Both direct attachments and Comment attachments require
-- an active Post; therefore moderating/removing content revokes new access.
create or replace function public.can_download_community_attachment(
  p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (public.is_admin() or public.is_active_student())
    and exists (
      select 1
      from public.community_attachments a
      where a.storage_path = p_storage_path
        and a.status = 'ready'
        and (
          (
            a.post_id is not null
            and exists (
              select 1
              from public.community_posts p
              join public.communities c on c.id = p.community_id
              where p.id = a.post_id
                and p.status = 'active'
                and public.can_access_subject(c.subject_id)
            )
          )
          or
          (
            a.comment_id is not null
            and exists (
              select 1
              from public.community_comments cc
              join public.community_posts p on p.id = cc.post_id
              join public.communities c on c.id = p.community_id
              where cc.id = a.comment_id
                and cc.status = 'active'
                and p.status = 'active'
                and public.can_access_subject(c.subject_id)
            )
          )
        )
    );
$$;

-- An object may be uploaded only after the reservation RPC created its exact
-- metadata row.  The target must still be active, owned by this Student, and
-- inside a Subject that the Student is currently allowed to use.
create or replace function public.can_upload_community_attachment(
  p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_active_student()
    and exists (
      select 1
      from public.community_attachments a
      where a.storage_path = p_storage_path
        and a.uploaded_by = auth.uid()
        and a.status = 'uploading'
        and a.created_at >= now() - interval '30 minutes'
        and (
          (
            a.post_id is not null
            and exists (
              select 1
              from public.community_posts p
              join public.communities c on c.id = p.community_id
              where p.id = a.post_id
                and p.author_id = auth.uid()
                and p.status = 'active'
                and public.can_access_subject(c.subject_id)
            )
          )
          or
          (
            a.comment_id is not null
            and exists (
              select 1
              from public.community_comments cc
              join public.community_posts p on p.id = cc.post_id
              join public.communities c on c.id = p.community_id
              where cc.id = a.comment_id
                and cc.author_id = auth.uid()
                and cc.status = 'active'
                and p.status = 'active'
                and public.can_access_subject(c.subject_id)
            )
          )
        )
    );
$$;

-- Ready bytes cannot be deleted directly.  The author first calls the removal
-- RPC, which changes metadata to removed; then either that active Student or an
-- active Admin may physically clean up the private object.
create or replace function public.can_delete_community_attachment(
  p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.community_attachments a
    where a.storage_path = p_storage_path
      and a.status in ('uploading', 'removed')
      and (
        public.is_admin()
        or (public.is_active_student() and a.uploaded_by = auth.uid())
      )
  );
$$;

-- Reserve one safe path and metadata row.  Uploading happens afterward because
-- PostgreSQL and Storage cannot share one transaction.  All relational checks,
-- ownership checks, idempotency, and the three-file limit are atomic here.
create or replace function public.reserve_community_attachment(
  p_subject_id uuid,
  p_target_type text,
  p_target_id uuid,
  p_file_name text,
  p_mime_type text,
  p_size_bytes bigint,
  p_idempotency_key uuid
)
returns public.community_attachments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_target_type text := lower(btrim(coalesce(p_target_type, '')));
  v_file_name text := btrim(coalesce(p_file_name, ''));
  v_mime_type text := lower(btrim(coalesce(p_mime_type, '')));
  v_post_id uuid;
  v_comment_id uuid;
  v_attachment_id uuid;
  v_existing public.community_attachments;
  v_attachment public.community_attachments;
  v_count integer;
  v_recent_count integer;
  v_allocated_bytes bigint;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required'
      using errcode = '42501';
  end if;

  if p_subject_id is null or not public.can_access_subject(p_subject_id) then
    raise exception 'Subject is unavailable' using errcode = '42501';
  end if;

  if v_target_type not in ('post', 'comment') or p_target_id is null then
    raise exception 'A valid post or comment target is required'
      using errcode = '22023';
  end if;

  if p_idempotency_key is null then
    raise exception 'idempotency_key is required' using errcode = '22023';
  end if;

  if char_length(v_file_name) not between 1 and 180
    or position('/' in v_file_name) > 0
    or position(E'\\' in v_file_name) > 0
    or v_file_name ~ '[[:cntrl:]]'
  then
    raise exception 'File name must contain 1-180 safe characters'
      using errcode = '22023';
  end if;

  if v_mime_type not in (
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'text/plain'
  ) then
    raise exception 'This attachment type is not supported'
      using errcode = '22023';
  end if;

  if not (
    (v_mime_type = 'image/jpeg' and lower(v_file_name) ~ '[.](jpg|jpeg)$')
    or (v_mime_type = 'image/png' and lower(v_file_name) ~ '[.]png$')
    or (v_mime_type = 'image/webp' and lower(v_file_name) ~ '[.]webp$')
    or (v_mime_type = 'application/pdf' and lower(v_file_name) ~ '[.]pdf$')
    or (v_mime_type = 'text/plain' and lower(v_file_name) ~ '[.]txt$')
  ) then
    raise exception 'File extension does not match its attachment type'
      using errcode = '22023';
  end if;

  if p_size_bytes is null or p_size_bytes not between 1 and 10485760 then
    raise exception 'Attachment size must be between 1 byte and 10 MiB'
      using errcode = '22023';
  end if;

  -- A user may attach a file only to content that the same user authored.
  if v_target_type = 'post' then
    select p.id into v_post_id
    from public.community_posts p
    join public.communities c on c.id = p.community_id
    where p.id = p_target_id
      and p.author_id = v_user_id
      and p.status = 'active'
      and c.subject_id = p_subject_id;

    if v_post_id is null then
      raise exception 'Post is unavailable or is not owned by this Student'
        using errcode = '42501';
    end if;
  else
    select cc.id into v_comment_id
    from public.community_comments cc
    join public.community_posts p on p.id = cc.post_id
    join public.communities c on c.id = p.community_id
    where cc.id = p_target_id
      and cc.author_id = v_user_id
      and cc.status = 'active'
      and p.status = 'active'
      and c.subject_id = p_subject_id;

    if v_comment_id is null then
      raise exception 'Comment is unavailable or is not owned by this Student'
        using errcode = '42501';
    end if;
  end if;

  -- Serialize all reservations for this Student before applying per-user rate
  -- and storage quotas, then serialize this target's three-file count.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('community-attachment-user:' || v_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_target_type || ':' || p_target_id::text, 0)
  );

  -- A phone can be closed after reserving but before finishing an upload.  A
  -- thirty-minute deadline releases that abandoned slot without ever making
  -- its possible object downloadable.  The cleanup Edge Function later removes
  -- any corresponding private byte while retaining this small audit record.
  update public.community_attachments a
  set status = 'removed',
      removal_reason = 'Upload reservation expired',
      removed_at = now(),
      removed_by = null
  where a.status = 'uploading'
    and a.created_at < now() - interval '30 minutes'
    and (
      (v_post_id is not null and a.post_id = v_post_id)
      or (v_comment_id is not null and a.comment_id = v_comment_id)
    );

  -- Check a retry before applying the count limit.  A repeated request returns
  -- the same reserved path and never consumes another attachment slot.
  select * into v_existing
  from public.community_attachments
  where uploaded_by = v_user_id
    and idempotency_key = p_idempotency_key
  for update;

  if v_existing.id is not null then
    if v_existing.post_id is distinct from v_post_id
      or v_existing.comment_id is distinct from v_comment_id
      or v_existing.file_name <> v_file_name
      or v_existing.mime_type <> v_mime_type
      or v_existing.size_bytes <> p_size_bytes
    then
      raise exception 'idempotency_key was already used for another attachment request'
        using errcode = '23505';
    end if;

    -- Return a removed/expired row so this transaction commits its expiration.
    -- The phone treats that status as terminal and creates a fresh request key.
    if v_existing.status = 'removed' then
      return v_existing;
    end if;

    return v_existing;
  end if;

  -- Bound automated abuse without affecting normal retries (handled above).
  select count(*)::integer into v_recent_count
  from public.community_attachments a
  where a.uploaded_by = v_user_id
    and a.created_at >= now() - interval '1 minute';

  if v_recent_count >= 10 then
    raise exception 'Please wait before reserving more attachments'
      using errcode = '54000';
  end if;

  -- Removed bytes still count until protected cleanup confirms their physical
  -- deletion.  Each Student may retain at most 100 MiB in this free-tier app.
  select coalesce(sum(a.size_bytes), 0) into v_allocated_bytes
  from public.community_attachments a
  where a.uploaded_by = v_user_id
    and a.storage_deleted_at is null;

  if v_allocated_bytes + p_size_bytes > 104857600 then
    raise exception 'Community attachment storage limit is 100 MiB per Student'
      using errcode = '54000';
  end if;

  select count(*)::integer into v_count
  from public.community_attachments a
  where a.status <> 'removed'
    and (
      (v_post_id is not null and a.post_id = v_post_id)
      or (v_comment_id is not null and a.comment_id = v_comment_id)
    );

  if v_count >= 3 then
    raise exception 'A Post or Comment can contain at most 3 attachments'
      using errcode = '23514';
  end if;

  v_attachment_id := gen_random_uuid();

  insert into public.community_attachments (
    id,
    post_id,
    comment_id,
    uploaded_by,
    file_name,
    storage_path,
    mime_type,
    size_bytes,
    status,
    idempotency_key
  ) values (
    v_attachment_id,
    v_post_id,
    v_comment_id,
    v_user_id,
    v_file_name,
    v_user_id::text || '/' || v_attachment_id::text,
    v_mime_type,
    p_size_bytes,
    'uploading',
    p_idempotency_key
  )
  returning * into v_attachment;

  return v_attachment;
end;
$$;

-- Only the protected Edge Function may complete an upload.  It downloads and
-- validates the real bytes first, then supplies their server-computed SHA-256.
-- Normal authenticated clients receive no EXECUTE grant for this function.
create or replace function public.complete_community_attachment(
  p_attachment_id uuid,
  p_checksum text
)
returns public.community_attachments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_checksum text := lower(btrim(coalesce(p_checksum, '')));
  v_attachment public.community_attachments;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only the attachment verification service may complete uploads'
      using errcode = '42501';
  end if;

  if p_attachment_id is null or v_checksum !~ '^[0-9a-f]{64}$' then
    raise exception 'A valid attachment id and SHA-256 checksum are required'
      using errcode = '22023';
  end if;

  select * into v_attachment
  from public.community_attachments
  where id = p_attachment_id
  for update;

  if v_attachment.id is null then
    raise exception 'Attachment was not found' using errcode = 'P0002';
  end if;

  -- A lost Edge response may safely repeat the exact verified completion.
  if v_attachment.status = 'ready' then
    if v_attachment.checksum = v_checksum then
      return v_attachment;
    end if;
    raise exception 'Attachment checksum conflicts with its completed upload'
      using errcode = '23514';
  end if;

  if v_attachment.status <> 'uploading' then
    raise exception 'A removed attachment cannot be finalized'
      using errcode = '55000';
  end if;

  if v_attachment.created_at < now() - interval '30 minutes' then
    raise exception 'Attachment reservation expired'
      using errcode = '55000';
  end if;

  if not exists (
    select 1
    from public.profiles pr
    where pr.id = v_attachment.uploaded_by
      and pr.role = 'student'
      and pr.status = 'active'
  ) then
    raise exception 'Attachment author is no longer an active Student'
      using errcode = '42501';
  end if;

  -- Recheck the entire active School-to-target path while holding the row lock.
  -- If moderation wins this race, verified bytes remain private and invisible.
  if not (
    (
      v_attachment.post_id is not null
      and exists (
        select 1
        from public.community_posts p
        join public.communities c on c.id = p.community_id
        join public.subjects s on s.id = c.subject_id
        join public.departments d on d.id = s.department_id
        join public.academic_areas a on a.id = d.area_id
        join public.schools sc on sc.id = a.school_id
        where p.id = v_attachment.post_id
          and p.author_id = v_attachment.uploaded_by
          and p.status = 'active'
          and s.status = 'active'
          and d.status = 'active'
          and a.status = 'active'
          and sc.status = 'active'
      )
    )
    or
    (
      v_attachment.comment_id is not null
      and exists (
        select 1
        from public.community_comments cc
        join public.community_posts p on p.id = cc.post_id
        join public.communities c on c.id = p.community_id
        join public.subjects s on s.id = c.subject_id
        join public.departments d on d.id = s.department_id
        join public.academic_areas a on a.id = d.area_id
        join public.schools sc on sc.id = a.school_id
        where cc.id = v_attachment.comment_id
          and cc.author_id = v_attachment.uploaded_by
          and cc.status = 'active'
          and p.status = 'active'
          and s.status = 'active'
          and d.status = 'active'
          and a.status = 'active'
          and sc.status = 'active'
      )
    )
  ) then
    raise exception 'Attachment target is no longer available'
      using errcode = '55000';
  end if;

  update public.community_attachments
  set status = 'ready', checksum = v_checksum
  where id = p_attachment_id
  returning * into v_attachment;

  return v_attachment;
end;
$$;

-- Soft-remove metadata first so no new download URL can be issued.  The client
-- receives the row (including its path) and then deletes the private byte.
create or replace function public.remove_community_attachment(
  p_attachment_id uuid,
  p_reason text default null
)
returns public.community_attachments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_reason text := coalesce(
    nullif(btrim(coalesce(p_reason, '')), ''),
    'Removed by author'
  );
  v_attachment public.community_attachments;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required'
      using errcode = '42501';
  end if;

  if p_attachment_id is null then
    raise exception 'attachment_id is required' using errcode = '22023';
  end if;

  if char_length(v_reason) not between 3 and 500 then
    raise exception 'Removal reason must contain 3-500 characters'
      using errcode = '22023';
  end if;

  select * into v_attachment
  from public.community_attachments
  where id = p_attachment_id
  for update;

  if v_attachment.id is null then
    raise exception 'Attachment was not found' using errcode = 'P0002';
  end if;

  if v_attachment.uploaded_by <> v_user_id then
    raise exception 'Only the attachment author may remove it'
      using errcode = '42501';
  end if;

  -- Repeating a successful removal is harmless and returns the same row.
  if v_attachment.status = 'removed' then
    return v_attachment;
  end if;

  update public.community_attachments
  set status = 'removed',
      removal_reason = v_reason,
      removed_at = now(),
      removed_by = v_user_id
  where id = p_attachment_id
  returning * into v_attachment;

  return v_attachment;
end;
$$;

-- Removing a Post hides both its own attachments and every attachment under
-- its Comments.  Removing one Comment hides only that Comment's attachments.
-- The same rule covers author deletion and Admin moderation automatically.
create or replace function public.hide_removed_content_attachments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'active' and new.status = 'removed' then
    if tg_table_name = 'community_posts' then
      update public.community_attachments a
      set status = 'removed',
          removal_reason = 'Parent Post was removed',
          removed_at = now(),
          removed_by = new.removed_by
      where a.status <> 'removed'
        and (
          a.post_id = new.id
          or a.comment_id in (
            select cc.id
            from public.community_comments cc
            where cc.post_id = new.id
          )
        );
    elsif tg_table_name = 'community_comments' then
      update public.community_attachments a
      set status = 'removed',
          removal_reason = 'Parent Comment was removed',
          removed_at = now(),
          removed_by = new.removed_by
      where a.comment_id = new.id
        and a.status <> 'removed';
    end if;
  end if;

  return new;
end;
$$;

create trigger community_posts_hide_attachments
after update of status on public.community_posts
for each row execute function public.hide_removed_content_attachments();

create trigger community_comments_hide_attachments
after update of status on public.community_comments
for each row execute function public.hide_removed_content_attachments();

-- Clients may read permitted metadata, but all writes stay behind the narrow
-- RPCs above.  This prevents phones from inventing paths, owners, or statuses.
alter table public.community_attachments enable row level security;

create policy community_attachments_read
on public.community_attachments
for select to authenticated
using (
  public.is_admin()
  or public.can_download_community_attachment(storage_path)
  or (
    status = 'uploading'
    and uploaded_by = auth.uid()
    and public.can_upload_community_attachment(storage_path)
  )
);

revoke all on table public.community_attachments from anon, authenticated;
grant select on table public.community_attachments to authenticated;

-- Close every SECURITY DEFINER function first, then expose only the operations
-- authenticated clients or their RLS policies need.
revoke execute on function public.can_download_community_attachment(text)
  from public, anon, authenticated;
revoke execute on function public.can_upload_community_attachment(text)
  from public, anon, authenticated;
revoke execute on function public.can_delete_community_attachment(text)
  from public, anon, authenticated;
revoke execute on function public.reserve_community_attachment(
  uuid, text, uuid, text, text, bigint, uuid
) from public, anon, authenticated;
revoke execute on function public.complete_community_attachment(uuid, text)
  from public, anon, authenticated, service_role;
revoke execute on function public.remove_community_attachment(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.hide_removed_content_attachments()
  from public, anon, authenticated;

grant execute on function public.can_download_community_attachment(text)
  to authenticated;
grant execute on function public.can_upload_community_attachment(text)
  to authenticated;
grant execute on function public.can_delete_community_attachment(text)
  to authenticated;
grant execute on function public.reserve_community_attachment(
  uuid, text, uuid, text, text, bigint, uuid
) to authenticated;
grant execute on function public.complete_community_attachment(uuid, text)
  to service_role;
grant execute on function public.remove_community_attachment(uuid, text)
  to authenticated;

-- Create/update the separate private bucket.  The bucket repeats the same type
-- and ten-MiB limits so unsafe bytes are rejected before they reach metadata.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'community-attachments',
  'community-attachments',
  false,
  10485760,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'text/plain'
  ]::text[]
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Reading object bytes requires ready metadata and an active visible target.
create policy community_attachments_objects_read
on storage.objects
for select to authenticated
using (
  bucket_id = 'community-attachments'
  and public.can_download_community_attachment(name)
);

-- Upload is insert-only, must match a reserved path, and cannot use upsert.
create policy community_attachments_objects_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'community-attachments'
  and public.can_upload_community_attachment(name)
);

-- A failed upload or soft-removed attachment can be physically cleaned up.
-- There is intentionally no UPDATE policy, so a ready object is immutable.
create policy community_attachments_objects_delete
on storage.objects
for delete to authenticated
using (
  bucket_id = 'community-attachments'
  and public.can_delete_community_attachment(name)
);

-- Publish metadata finalization/removal so an open Community screen refreshes
-- when an upload becomes ready or moderation hides it.
alter table public.community_attachments replica identity default;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'community_attachments'
  ) then
    execute 'alter publication supabase_realtime add table public.community_attachments';
  end if;
end;
$$;

commit;
