-- Safe, permanent deletion for Admin-owned Subjects and official PDF files.
--
-- PostgreSQL and Supabase Storage cannot participate in one transaction.  The
-- workflow below therefore uses a durable two-phase job:
--
--   1. prepare locks the catalog, retires linked quizzes, and snapshots paths;
--   2. the authenticated Admin client deletes exactly those Storage objects;
--   3. finalize proves every recorded object is absent, then deletes DB rows.
--
-- Quiz definitions and Student attempts are historical records.  They are
-- detached from deleted live catalog rows with ON DELETE SET NULL while their
-- immutable Subject/material snapshots remain available to history screens.
-- Community Posts are also Student-owned history, so a Subject containing any
-- Post is protected from permanent deletion.

begin;

-- ---------------------------------------------------------------------------
-- Preserve Quiz and Attempt history before changing the live foreign keys.
-- ---------------------------------------------------------------------------

alter table public.quizzes
  add column if not exists subject_id_snapshot uuid,
  add column if not exists material_id_snapshot uuid,
  add column if not exists subject_name_snapshot text,
  add column if not exists material_title_snapshot text,
  add column if not exists material_checksum_snapshot text;

update public.quizzes q
set subject_id_snapshot = q.subject_id,
    material_id_snapshot = q.material_id,
    subject_name_snapshot = s.name,
    material_title_snapshot = m.title,
    material_checksum_snapshot = m.checksum
from public.subjects s, public.subject_materials m
where s.id = q.subject_id
  and m.id = q.material_id
  and (
    q.subject_id_snapshot is null
    or q.material_id_snapshot is null
    or q.subject_name_snapshot is null
    or q.material_title_snapshot is null
  );

alter table public.quizzes
  alter column subject_id_snapshot set not null,
  alter column material_id_snapshot set not null,
  alter column subject_name_snapshot set not null,
  alter column material_title_snapshot set not null,
  alter column material_checksum_snapshot set not null;

alter table public.quizzes
  drop constraint if exists quizzes_subject_id_fkey,
  drop constraint if exists quizzes_material_id_fkey,
  drop constraint if exists quizzes_live_catalog_check;

alter table public.quizzes
  alter column subject_id drop not null,
  alter column material_id drop not null;

alter table public.quizzes
  add constraint quizzes_subject_id_fkey
    foreign key (subject_id) references public.subjects(id) on delete set null,
  add constraint quizzes_material_id_fkey
    foreign key (material_id) references public.subject_materials(id) on delete set null,
  add constraint quizzes_live_catalog_check check (
    status = 'retired' or (subject_id is not null and material_id is not null)
  );

alter table public.quiz_attempts
  add column if not exists subject_id_snapshot uuid;

update public.quiz_attempts qa
set subject_id_snapshot = q.subject_id_snapshot
from public.quizzes q
where q.id = qa.quiz_id
  and qa.subject_id_snapshot is null;

alter table public.quiz_attempts
  alter column subject_id_snapshot set not null,
  drop constraint if exists quiz_attempts_subject_id_fkey;

alter table public.quiz_attempts
  alter column subject_id drop not null;

alter table public.quiz_attempts
  add constraint quiz_attempts_subject_id_fkey
    foreign key (subject_id) references public.subjects(id) on delete set null;

create index if not exists quizzes_subject_id_idx
  on public.quizzes (subject_id) where subject_id is not null;
create index if not exists quizzes_material_id_idx
  on public.quizzes (material_id) where material_id is not null;
create index if not exists quiz_attempts_subject_id_idx
  on public.quiz_attempts (subject_id) where subject_id is not null;
create index if not exists quiz_attempts_student_subject_snapshot_idx
  on public.quiz_attempts (student_id, subject_id_snapshot, completed_at desc);

-- Every new Quiz is snapshotted from a locked, live catalog context.  The row
-- locks serialize AI generation with Subject/PDF preparation.  Later FK-driven
-- detachment is accepted only after the Quiz has already been retired.
create or replace function public.enforce_quiz_catalog_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject_name text;
  v_material_title text;
  v_material_checksum text;
begin
  if tg_op = 'UPDATE' then
    if new.subject_id_snapshot is distinct from old.subject_id_snapshot
      or new.material_id_snapshot is distinct from old.material_id_snapshot
      or new.subject_name_snapshot is distinct from old.subject_name_snapshot
      or new.material_title_snapshot is distinct from old.material_title_snapshot
      or new.material_checksum_snapshot is distinct from old.material_checksum_snapshot
    then
      raise exception 'Quiz catalog snapshots are immutable' using errcode = '23514';
    end if;

    if new.subject_id is distinct from old.subject_id
      and not (
        old.subject_id is not null
        and new.subject_id is null
        and new.status = 'retired'
      )
    then
      raise exception 'A Quiz cannot move to another Subject' using errcode = '23514';
    end if;

    if new.material_id is distinct from old.material_id
      and not (
        old.material_id is not null
        and new.material_id is null
        and new.status = 'retired'
      )
    then
      raise exception 'A Quiz cannot move to another PDF' using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' or new.status = 'ready' then
    if new.subject_id is null or new.material_id is null then
      raise exception 'A ready Quiz requires a live Subject and PDF'
        using errcode = '23514';
    end if;

    select s.name, m.title, m.checksum
    into v_subject_name, v_material_title, v_material_checksum
    from public.subjects s
    join public.subject_materials m
      on m.id = new.material_id and m.subject_id = s.id
    where s.id = new.subject_id
      and s.status = 'active'
      and m.status = 'approved'
    for key share of s, m;

    if not found then
      raise exception 'The Quiz Subject or approved PDF is no longer available'
        using errcode = '23503';
    end if;

    if tg_op = 'INSERT' then
      new.subject_id_snapshot := new.subject_id;
      new.material_id_snapshot := new.material_id;
      new.subject_name_snapshot := v_subject_name;
      new.material_title_snapshot := v_material_title;
      new.material_checksum_snapshot := v_material_checksum;
    elsif new.subject_id is distinct from new.subject_id_snapshot
      or new.material_id is distinct from new.material_id_snapshot
    then
      raise exception 'A ready Quiz must use its original Subject and PDF'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists quizzes_enforce_catalog_context on public.quizzes;
drop trigger if exists quizzes_00_enforce_catalog_context on public.quizzes;
create trigger quizzes_00_enforce_catalog_context
before insert or update on public.quizzes
for each row execute function public.enforce_quiz_catalog_context();

-- An Attempt keeps its immutable Subject snapshot even after its live Subject
-- link is set to NULL.  New attempts require a locked, ready Quiz; this makes a
-- concurrent Quiz retirement win cleanly instead of accepting a late score.
create or replace function public.enforce_attempt_subject()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quiz_subject_id uuid;
  v_quiz_subject_snapshot uuid;
  v_quiz_status text;
begin
  select q.subject_id, q.subject_id_snapshot, q.status
  into v_quiz_subject_id, v_quiz_subject_snapshot, v_quiz_status
  from public.quizzes q
  where q.id = new.quiz_id
  for no key update;

  if not found then
    raise exception 'Quiz was not found' using errcode = '23503';
  end if;

  if tg_op = 'INSERT' then
    if v_quiz_status <> 'ready' or v_quiz_subject_id is null then
      raise exception 'This Quiz is retired and cannot accept new attempts'
        using errcode = '55000';
    end if;
    if new.subject_id is distinct from v_quiz_subject_id then
      raise exception 'Attempt Subject must match Quiz Subject' using errcode = '23514';
    end if;
    new.subject_id_snapshot := v_quiz_subject_snapshot;
    return new;
  end if;

  if new.quiz_id is distinct from old.quiz_id then
    raise exception 'An Attempt cannot move to another Quiz' using errcode = '23514';
  end if;
  if new.subject_id_snapshot is distinct from old.subject_id_snapshot then
    raise exception 'Attempt Subject snapshot is immutable' using errcode = '23514';
  end if;
  if new.subject_id is distinct from old.subject_id
    and not (
      old.subject_id is not null
      and new.subject_id is null
      and v_quiz_status = 'retired'
    )
  then
    raise exception 'An Attempt cannot move to another Subject' using errcode = '23514';
  end if;

  if v_quiz_status = 'ready'
    and new.subject_id is distinct from v_quiz_subject_id
  then
    raise exception 'Attempt Subject must match Quiz Subject' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists quiz_attempts_enforce_subject on public.quiz_attempts;
create trigger quiz_attempts_enforce_subject
before insert or update on public.quiz_attempts
for each row execute function public.enforce_attempt_subject();

-- A Subject can be removed only after its one Community is explicitly removed.
-- A Community can be removed only while it is empty.  RESTRICT is intentional:
-- no raw/service-role delete may cascade through Student Posts.
alter table public.communities
  drop constraint if exists communities_subject_id_fkey;
alter table public.communities
  add constraint communities_subject_id_fkey
    foreign key (subject_id) references public.subjects(id) on delete restrict;

alter table public.community_posts
  drop constraint if exists community_posts_community_id_fkey;
alter table public.community_posts
  add constraint community_posts_community_id_fkey
    foreign key (community_id) references public.communities(id) on delete restrict;

-- ---------------------------------------------------------------------------
-- Durable deletion jobs and their immutable material/path ledger.
-- ---------------------------------------------------------------------------

-- Keep every path ever assigned to a material, not only its current path.  PDF
-- replacement changes subject_materials.storage_path before deleting the old
-- object, so a current-row-only snapshot could otherwise strand old bytes.
create table if not exists public.subject_material_storage_objects (
  material_id uuid not null references public.subject_materials(id) on delete cascade,
  subject_id uuid not null,
  storage_path text not null,
  recorded_at timestamptz not null default now(),
  primary key (material_id, storage_path),
  constraint subject_material_storage_objects_path_key unique (storage_path),
  constraint subject_material_storage_objects_path_check check (
    char_length(storage_path) between 5 and 1000
    and storage_path = btrim(storage_path)
    and storage_path not like '/%'
  )
);

insert into public.subject_material_storage_objects (
  material_id, subject_id, storage_path
)
select m.id, m.subject_id, m.storage_path
from public.subject_materials m
on conflict (material_id, storage_path) do nothing;

create or replace function public.remember_subject_material_storage_object()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.subject_material_storage_objects (
    material_id, subject_id, storage_path
  ) values (
    new.id, new.subject_id, new.storage_path
  )
  on conflict (material_id, storage_path) do nothing;
  return new;
end;
$$;

drop trigger if exists subject_materials_remember_storage_object
  on public.subject_materials;
create trigger subject_materials_remember_storage_object
after insert or update of storage_path on public.subject_materials
for each row execute function public.remember_subject_material_storage_object();

create table if not exists public.admin_catalog_deletion_jobs (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  subject_id uuid,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  reason text not null,
  storage_paths text[] not null default array[]::text[],
  dependency_counts jsonb not null default '{}'::jsonb,
  status text not null default 'prepared',
  storage_verified_at timestamptz,
  storage_verified_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  completed_by uuid references public.profiles(id) on delete set null,
  constraint admin_catalog_deletion_jobs_entity_check
    check (entity_type in ('material', 'subject')),
  constraint admin_catalog_deletion_jobs_reason_check
    check (char_length(btrim(reason)) between 3 and 500),
  constraint admin_catalog_deletion_jobs_counts_check
    check (jsonb_typeof(dependency_counts) = 'object'),
  constraint admin_catalog_deletion_jobs_status_check
    check (status in ('prepared', 'completed')),
  constraint admin_catalog_deletion_jobs_completion_check check (
    (
      status = 'prepared'
      and storage_verified_at is null
      and storage_verified_by is null
      and completed_at is null
      and completed_by is null
    )
    or
    (
      status = 'completed'
      and storage_verified_at is not null
      and storage_verified_by is not null
      and completed_at is not null
      and completed_by is not null
    )
  )
);

create table if not exists public.admin_catalog_deletion_material_storage_objects (
  job_id uuid not null references public.admin_catalog_deletion_jobs(id) on delete restrict,
  material_id uuid not null,
  subject_id uuid not null,
  storage_path text not null,
  recorded_at timestamptz not null default now(),
  verified_absent_at timestamptz,
  verified_absent_by uuid references public.profiles(id) on delete set null,
  primary key (job_id, material_id, storage_path),
  constraint admin_catalog_deletion_material_storage_objects_path_key
    unique (job_id, storage_path),
  constraint admin_catalog_deletion_material_storage_objects_path_check check (
    char_length(storage_path) between 5 and 1000
    and storage_path = btrim(storage_path)
    and storage_path not like '/%'
  ),
  constraint admin_catalog_deletion_material_storage_objects_proof_check check (
    (verified_absent_at is null and verified_absent_by is null)
    or
    (verified_absent_at is not null and verified_absent_by is not null)
  )
);

create unique index if not exists admin_catalog_deletion_jobs_prepared_key
  on public.admin_catalog_deletion_jobs (entity_type, entity_id)
  where status = 'prepared';
create index if not exists admin_catalog_deletion_jobs_status_created_idx
  on public.admin_catalog_deletion_jobs (status, created_at);
create index if not exists admin_catalog_deletion_material_storage_objects_path_idx
  on public.admin_catalog_deletion_material_storage_objects (storage_path, job_id);

alter table public.admin_catalog_deletion_jobs enable row level security;
alter table public.admin_catalog_deletion_material_storage_objects enable row level security;
alter table public.subject_material_storage_objects enable row level security;
revoke all on table public.admin_catalog_deletion_jobs from anon, authenticated;
revoke all on table public.admin_catalog_deletion_material_storage_objects from anon, authenticated;
revoke all on table public.subject_material_storage_objects from anon, authenticated;

-- Storage INSERT calls this function inside the authenticated object-write
-- transaction.  FOR KEY SHARE remains held until that transaction commits, so
-- prepare (which takes FOR UPDATE) cannot snapshot/delete ahead of a late upload.
create or replace function public.can_upload_subject_material_object(
  p_storage_path text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_material_id uuid;
  v_subject_id uuid;
  v_status text;
begin
  if auth.uid() is null or not public.is_admin() then
    return false;
  end if;

  select m.id, m.subject_id, m.status
  into v_material_id, v_subject_id, v_status
  from public.subject_materials m
  where m.storage_path = p_storage_path
  for key share;

  if not found or v_status <> 'uploading' then
    return false;
  end if;

  return exists (
    select 1
    from public.subjects s
    where s.id = v_subject_id and s.status = 'active'
  ) and not exists (
    select 1
    from public.admin_catalog_deletion_jobs j
    where j.status = 'prepared'
      and (
        (j.entity_type = 'material' and j.entity_id = v_material_id)
        or
        (j.entity_type = 'subject' and j.entity_id = v_subject_id)
      )
  );
end;
$$;

-- Storage DELETE is limited to a prepared/completed ledger path, an explicitly
-- removed material, or an unreferenced orphan (needed for replacement cleanup).
create or replace function public.can_delete_subject_material_object(
  p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.is_admin()
    and (
      exists (
        select 1
        from public.admin_catalog_deletion_material_storage_objects o
        where o.storage_path = p_storage_path
      )
      or exists (
        select 1
        from public.subject_materials m
        where m.storage_path = p_storage_path and m.status = 'removed'
      )
      or not exists (
        select 1
        from public.subject_materials m
        where m.storage_path = p_storage_path
      )
    );
$$;

-- Block catalog mutations after prepare.  OLD and NEW are both inspected so a
-- writer cannot evade the barrier by moving a row away from the deleting key.
-- The two narrowly defined SET NULL shapes are PostgreSQL's FK actions during
-- finalization; all other changes stay blocked.
create or replace function public.block_pending_catalog_deletion_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject_id uuid;
  v_material_id uuid;
  v_safe_fk_detach boolean := false;
  v_quiz_status text;
begin
  if tg_table_name = 'subjects' then
    if new.id is distinct from old.id then
      raise exception 'A Subject id cannot be changed' using errcode = '23514';
    end if;
    v_subject_id := old.id;

  elsif tg_table_name = 'subject_materials' then
    if tg_op = 'INSERT' then
      -- This explicit lock is acquired before the FK check and serializes a new
      -- material with Subject preparation, which holds FOR UPDATE on Subject.
      perform 1
      from public.subjects s
      where s.id = new.subject_id
      for key share;
      if not found then
        raise exception 'Subject was not found' using errcode = '23503';
      end if;
      v_subject_id := new.subject_id;
      v_material_id := new.id;
    else
      if new.id is distinct from old.id then
        raise exception 'A PDF id cannot be changed' using errcode = '23514';
      end if;
      if new.subject_id is distinct from old.subject_id then
        raise exception 'A PDF cannot move to another Subject' using errcode = '23514';
      end if;
      v_subject_id := old.subject_id;
      v_material_id := old.id;
    end if;

  elsif tg_table_name = 'quizzes' then
    if tg_op = 'INSERT' then
      v_subject_id := new.subject_id;
      v_material_id := new.material_id;
    else
      v_subject_id := coalesce(new.subject_id, old.subject_id, old.subject_id_snapshot);
      v_material_id := coalesce(new.material_id, old.material_id, old.material_id_snapshot);
      v_safe_fk_detach :=
        old.status = 'retired'
        and new.status = 'retired'
        and (
          new.subject_id is not distinct from old.subject_id
          or (old.subject_id is not null and new.subject_id is null)
        )
        and (
          new.material_id is not distinct from old.material_id
          or (old.material_id is not null and new.material_id is null)
        )
        and (
          new.subject_id is distinct from old.subject_id
          or new.material_id is distinct from old.material_id
        )
        and (to_jsonb(new) - 'subject_id' - 'material_id')
          = (to_jsonb(old) - 'subject_id' - 'material_id');
    end if;

  elsif tg_table_name = 'quiz_attempts' then
    v_subject_id := case
      when tg_op = 'INSERT' then coalesce(new.subject_id, new.subject_id_snapshot)
      else coalesce(new.subject_id, old.subject_id, old.subject_id_snapshot)
    end;

    select q.material_id, q.status
    into v_material_id, v_quiz_status
    from public.quizzes q
    where q.id = new.quiz_id;

    if tg_op = 'UPDATE' then
      v_safe_fk_detach :=
        old.subject_id is not null
        and new.subject_id is null
        and v_quiz_status = 'retired'
        and (to_jsonb(new) - 'subject_id') = (to_jsonb(old) - 'subject_id');
    end if;

  elsif tg_table_name = 'community_posts' then
    if tg_op = 'UPDATE' and new.community_id is distinct from old.community_id then
      raise exception 'A Post cannot move to another Community' using errcode = '23514';
    end if;

    -- Match Subject deletion's lock order: Subject first, then Community.  A
    -- Post that starts first commits and is detected; a Post that starts second
    -- waits and sees the prepared job instead of passing a stale check.
    select c.subject_id
    into v_subject_id
    from public.communities c
    where c.id = new.community_id;

    if not found then
      raise exception 'Community was not found' using errcode = '23503';
    end if;

    perform 1
    from public.subjects s
    where s.id = v_subject_id
    for key share;

    if not found then
      raise exception 'Subject was not found' using errcode = '23503';
    end if;

    perform 1
    from public.communities c
    where c.id = new.community_id and c.subject_id = v_subject_id
    for key share;

    if not found then
      raise exception 'Community was not found' using errcode = '23503';
    end if;
  end if;

  if exists (
    select 1
    from public.admin_catalog_deletion_jobs j
    where j.status = 'prepared'
      and (
        (j.entity_type = 'subject' and j.entity_id = v_subject_id)
        or
        (j.entity_type = 'material' and j.entity_id = v_material_id)
      )
  ) and not v_safe_fk_detach then
    raise exception 'Permanent deletion is already in progress. Retry that deletion first.'
      using errcode = '55000';
  end if;

  return new;
end;
$$;

drop trigger if exists subjects_block_pending_catalog_deletion on public.subjects;
create trigger subjects_block_pending_catalog_deletion
before update on public.subjects
for each row execute function public.block_pending_catalog_deletion_mutation();

drop trigger if exists materials_block_pending_catalog_deletion on public.subject_materials;
drop trigger if exists subject_materials_99_block_pending_catalog_deletion on public.subject_materials;
create trigger subject_materials_99_block_pending_catalog_deletion
before insert or update on public.subject_materials
for each row execute function public.block_pending_catalog_deletion_mutation();

drop trigger if exists quizzes_block_pending_catalog_deletion on public.quizzes;
drop trigger if exists quizzes_99_block_pending_catalog_deletion on public.quizzes;
create trigger quizzes_99_block_pending_catalog_deletion
before insert or update on public.quizzes
for each row execute function public.block_pending_catalog_deletion_mutation();

drop trigger if exists attempts_block_pending_catalog_deletion on public.quiz_attempts;
drop trigger if exists quiz_attempts_zz_block_pending_catalog_deletion on public.quiz_attempts;
create trigger quiz_attempts_zz_block_pending_catalog_deletion
before insert or update on public.quiz_attempts
for each row execute function public.block_pending_catalog_deletion_mutation();

drop trigger if exists posts_block_pending_catalog_deletion on public.community_posts;
drop trigger if exists community_posts_00_block_pending_catalog_deletion on public.community_posts;
create trigger community_posts_00_block_pending_catalog_deletion
before insert or update on public.community_posts
for each row execute function public.block_pending_catalog_deletion_mutation();

-- ---------------------------------------------------------------------------
-- Material deletion: prepare and finalize.
-- ---------------------------------------------------------------------------

create or replace function public.admin_prepare_material_deletion(
  p_material_id uuid,
  p_expected_version integer,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_material public.subject_materials;
  v_job public.admin_catalog_deletion_jobs;
  v_subject_id uuid;
  v_paths text[] := array[]::text[];
  v_storage_object_count integer := 0;
  v_quiz_count integer := 0;
  v_attempt_count integer := 0;
begin
  if v_admin_id is null or not public.is_admin() then
    raise exception 'An active Admin account is required' using errcode = '42501';
  end if;
  if p_material_id is null or p_expected_version is null or p_expected_version < 1 then
    raise exception 'A valid PDF id and version are required' using errcode = '22023';
  end if;
  if char_length(v_reason) not between 3 and 500 then
    raise exception 'Deletion reason must contain 3-500 characters' using errcode = '22023';
  end if;

  select * into v_job
  from public.admin_catalog_deletion_jobs j
  where j.entity_type = 'material'
    and j.entity_id = p_material_id
    and j.status = 'prepared'
  for update;

  if found then
    return jsonb_build_object(
      'outcome', 'prepared',
      'job_id', v_job.id,
      'material_id', v_job.entity_id,
      'subject_id', v_job.subject_id,
      'storage_paths', to_jsonb(v_job.storage_paths),
      'dependency_counts', v_job.dependency_counts
    );
  end if;

  -- Resolve the parent without locking the child, then follow the global lock
  -- order used by Subject prepare: Subject first, Material second.
  select m.subject_id into v_subject_id
  from public.subject_materials m
  where m.id = p_material_id;

  if not found then
    select * into v_job
    from public.admin_catalog_deletion_jobs j
    where j.entity_type = 'material'
      and j.entity_id = p_material_id
      and j.status = 'completed'
    order by j.completed_at desc
    limit 1
    for update;

    if found then
      return jsonb_build_object(
        'outcome', 'completed',
        'job_id', v_job.id,
        'material_id', v_job.entity_id,
        'subject_id', v_job.subject_id,
        'storage_paths', to_jsonb(v_job.storage_paths),
        'dependency_counts', v_job.dependency_counts
      );
    end if;

    return jsonb_build_object(
      'outcome', 'already_deleted',
      'material_id', p_material_id,
      'storage_paths', '[]'::jsonb,
      'dependency_counts', '{}'::jsonb
    );
  end if;

  perform 1
  from public.subjects s
  where s.id = v_subject_id
  for update;

  if not found then
    raise exception 'The PDF Subject no longer exists. Refresh and retry.'
      using errcode = '40001';
  end if;

  select * into v_material
  from public.subject_materials m
  where m.id = p_material_id
  for update;

  if not found then
    -- A finalizer may have completed while this request waited for Subject.
    select * into v_job
    from public.admin_catalog_deletion_jobs j
    where j.entity_type = 'material'
      and j.entity_id = p_material_id
      and j.status = 'completed'
    order by j.completed_at desc
    limit 1
    for update;

    if found then
      return jsonb_build_object(
        'outcome', 'completed',
        'job_id', v_job.id,
        'material_id', v_job.entity_id,
        'subject_id', v_job.subject_id,
        'storage_paths', to_jsonb(v_job.storage_paths),
        'dependency_counts', v_job.dependency_counts
      );
    end if;

    return jsonb_build_object(
      'outcome', 'already_deleted',
      'material_id', p_material_id,
      'storage_paths', '[]'::jsonb,
      'dependency_counts', '{}'::jsonb
    );
  end if;

  -- A second Admin may have waited on the same PDF lock.
  select * into v_job
  from public.admin_catalog_deletion_jobs j
  where j.entity_type = 'material'
    and j.entity_id = p_material_id
    and j.status = 'prepared'
  for update;

  if found then
    return jsonb_build_object(
      'outcome', 'prepared',
      'job_id', v_job.id,
      'material_id', v_job.entity_id,
      'subject_id', v_job.subject_id,
      'storage_paths', to_jsonb(v_job.storage_paths),
      'dependency_counts', v_job.dependency_counts
    );
  end if;

  if exists (
    select 1
    from public.admin_catalog_deletion_jobs j
    where j.entity_type = 'subject'
      and j.entity_id = v_material.subject_id
      and j.status = 'prepared'
  ) then
    raise exception 'This Subject is already being deleted. Retry the Subject deletion.'
      using errcode = '55000';
  end if;

  if v_material.version <> p_expected_version then
    raise exception 'This PDF changed on another Admin device. Refresh and try again.'
      using errcode = '40001';
  end if;

  select coalesce(array_agg(o.storage_path order by o.storage_path), array[]::text[]),
         count(*)::integer
  into v_paths, v_storage_object_count
  from public.subject_material_storage_objects o
  where o.material_id = p_material_id;

  if v_storage_object_count = 0
    or not (v_material.storage_path = any(v_paths))
  then
    raise exception 'The PDF Storage path history is incomplete. Repair it before deletion.'
      using errcode = '55000';
  end if;

  select count(*)::integer into v_quiz_count
  from public.quizzes q
  where q.material_id = p_material_id;

  -- Lock/retire Quizzes before counting attempts.  Attempt insertion takes a
  -- NO KEY UPDATE lock on its Quiz, so no late score can appear after this count.
  update public.quizzes q
  set status = 'retired'
  where q.material_id = p_material_id and q.status <> 'retired';

  select count(*)::integer into v_attempt_count
  from public.quiz_attempts qa
  where qa.quiz_id in (
    select q.id from public.quizzes q where q.material_id = p_material_id
  );

  if v_material.status <> 'removed' then
    update public.subject_materials m
    set status = 'removed',
        removal_reason = v_reason,
        removed_at = now()
    where m.id = p_material_id;
  end if;

  insert into public.admin_catalog_deletion_jobs (
    entity_type, entity_id, subject_id, requested_by, reason,
    storage_paths, dependency_counts
  ) values (
    'material', p_material_id, v_material.subject_id, v_admin_id, v_reason,
    v_paths,
    jsonb_build_object(
      'materials', 1,
      'storage_objects', v_storage_object_count,
      'quizzes', v_quiz_count,
      'quiz_attempts', v_attempt_count
    )
  )
  returning * into v_job;

  insert into public.admin_catalog_deletion_material_storage_objects (
    job_id, material_id, subject_id, storage_path
  )
  select v_job.id, o.material_id, o.subject_id, o.storage_path
  from public.subject_material_storage_objects o
  where o.material_id = v_material.id
  order by o.storage_path;

  return jsonb_build_object(
    'outcome', 'prepared',
    'job_id', v_job.id,
    'material_id', v_job.entity_id,
    'subject_id', v_job.subject_id,
    'storage_paths', to_jsonb(v_job.storage_paths),
    'dependency_counts', v_job.dependency_counts
  );
end;
$$;

create or replace function public.admin_finalize_material_deletion(
  p_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_job public.admin_catalog_deletion_jobs;
  v_ledger_count integer := 0;
  v_preserved_quizzes integer := 0;
  v_preserved_attempts integer := 0;
  v_deleted_materials integer := 0;
  v_verified_at timestamptz := now();
begin
  if v_admin_id is null or not public.is_admin() then
    raise exception 'An active Admin account is required' using errcode = '42501';
  end if;
  if p_job_id is null then
    raise exception 'A valid deletion job id is required' using errcode = '22023';
  end if;

  select * into v_job
  from public.admin_catalog_deletion_jobs j
  where j.id = p_job_id
  for update;

  if not found or v_job.entity_type <> 'material' then
    raise exception 'PDF deletion job was not found' using errcode = 'P0002';
  end if;
  if v_job.status = 'completed' then
    return jsonb_build_object(
      'outcome', 'already_deleted',
      'job_id', v_job.id,
      'material_id', v_job.entity_id,
      'deleted_materials', 0,
      'preserved_quizzes', coalesce((v_job.dependency_counts ->> 'quizzes')::integer, 0),
      'preserved_attempts', coalesce((v_job.dependency_counts ->> 'quiz_attempts')::integer, 0),
      'preserved_quiz_attempts', coalesce((v_job.dependency_counts ->> 'quiz_attempts')::integer, 0)
    );
  end if;

  select count(*)::integer into v_ledger_count
  from public.admin_catalog_deletion_material_storage_objects o
  where o.job_id = v_job.id;

  if v_ledger_count < 1
    or v_ledger_count <> coalesce((v_job.dependency_counts ->> 'storage_objects')::integer, -1)
    or cardinality(v_job.storage_paths) <> v_ledger_count
    or exists (
      select 1
      from public.admin_catalog_deletion_material_storage_objects o
      where o.job_id = v_job.id
        and (
          o.material_id <> v_job.entity_id
          or o.subject_id is distinct from v_job.subject_id
          or not (o.storage_path = any(v_job.storage_paths))
        )
    )
    or exists (
      select 1
      from public.admin_catalog_deletion_material_storage_objects o
      where o.job_id = v_job.id
        and not exists (
          select 1
          from public.subject_material_storage_objects so
          where so.material_id = o.material_id
            and so.subject_id = o.subject_id
            and so.storage_path = o.storage_path
        )
    )
    or exists (
      select 1
      from public.subject_material_storage_objects so
      where so.material_id = v_job.entity_id
        and not exists (
          select 1
          from public.admin_catalog_deletion_material_storage_objects o
          where o.job_id = v_job.id
            and o.material_id = so.material_id
            and o.subject_id = so.subject_id
            and o.storage_path = so.storage_path
        )
    )
  then
    raise exception 'The PDF deletion path ledger is incomplete'
      using errcode = '55000';
  end if;

  -- Keep the same Subject -> Material lock order as both prepare functions.
  perform 1
  from public.subjects s
  where s.id = v_job.subject_id
  for update;

  -- Hold the target row while proving Storage absence and deleting metadata.
  perform 1
  from public.subject_materials m
  where m.id = v_job.entity_id
  for update;

  if exists (
    select 1
    from public.subject_materials m
    where m.id = v_job.entity_id
      and (
        m.subject_id is distinct from v_job.subject_id
        or m.status <> 'removed'
        or not exists (
          select 1
          from public.admin_catalog_deletion_material_storage_objects o
          where o.job_id = v_job.id
            and o.material_id = m.id
            and o.subject_id = m.subject_id
            and o.storage_path = m.storage_path
        )
      )
  ) then
    raise exception 'The PDF changed during permanent deletion. Refresh and retry.'
      using errcode = '40001';
  end if;

  if exists (
    select 1
    from storage.objects so
    join public.admin_catalog_deletion_material_storage_objects o
      on o.storage_path = so.name and o.job_id = v_job.id
    where so.bucket_id = 'subject-materials'
  ) then
    raise exception 'The private PDF file is not deleted yet. Check the connection and retry.'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from public.quizzes q
    where q.material_id = v_job.entity_id and q.status <> 'retired'
  ) then
    raise exception 'A linked Quiz is still active. Retry deletion.' using errcode = '55000';
  end if;

  select count(*)::integer into v_preserved_quizzes
  from public.quizzes q
  where q.material_id_snapshot = v_job.entity_id;

  select count(*)::integer into v_preserved_attempts
  from public.quiz_attempts qa
  where qa.quiz_id in (
    select q.id from public.quizzes q where q.material_id_snapshot = v_job.entity_id
  );

  update public.admin_catalog_deletion_material_storage_objects o
  set verified_absent_at = v_verified_at,
      verified_absent_by = v_admin_id
  where o.job_id = v_job.id;

  -- ON DELETE SET NULL detaches only the live material link.  Quiz snapshots
  -- and every Attempt row remain intact.
  delete from public.subject_materials m
  where m.id = v_job.entity_id;
  get diagnostics v_deleted_materials = row_count;

  update public.admin_catalog_deletion_jobs j
  set status = 'completed',
      storage_verified_at = v_verified_at,
      storage_verified_by = v_admin_id,
      completed_at = v_verified_at,
      completed_by = v_admin_id
  where j.id = v_job.id;

  insert into public.admin_audit_log (
    actor_id, action, entity_type, entity_id, details
  ) values (
    v_admin_id,
    'permanently_delete_material',
    'subject_material',
    v_job.entity_id,
    jsonb_build_object(
      'job_id', v_job.id,
      'subject_id', v_job.subject_id,
      'reason', v_job.reason,
      'storage_paths', to_jsonb(v_job.storage_paths),
      'storage_verified_at', v_verified_at,
      'deleted_materials', v_deleted_materials,
      'preserved_quizzes', v_preserved_quizzes,
      'preserved_attempts', v_preserved_attempts,
      'preserved_quiz_attempts', v_preserved_attempts,
      'requested_by', v_job.requested_by
    )
  );

  return jsonb_build_object(
    'outcome', case when v_deleted_materials = 0 then 'already_deleted' else 'deleted' end,
    'job_id', v_job.id,
    'material_id', v_job.entity_id,
    'deleted_materials', v_deleted_materials,
    'preserved_quizzes', v_preserved_quizzes,
    'preserved_attempts', v_preserved_attempts,
    'preserved_quiz_attempts', v_preserved_attempts
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Subject deletion: prepare every material/path, then finalize the empty shell.
-- ---------------------------------------------------------------------------

create or replace function public.admin_prepare_subject_deletion(
  p_subject_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_subject public.subjects;
  v_community_id uuid;
  v_job public.admin_catalog_deletion_jobs;
  v_paths text[] := array[]::text[];
  v_material_count integer := 0;
  v_storage_object_count integer := 0;
  v_quiz_count integer := 0;
  v_attempt_count integer := 0;
begin
  if v_admin_id is null or not public.is_admin() then
    raise exception 'An active Admin account is required' using errcode = '42501';
  end if;
  if p_subject_id is null then
    raise exception 'A valid Subject id is required' using errcode = '22023';
  end if;
  if char_length(v_reason) not between 3 and 500 then
    raise exception 'Deletion reason must contain 3-500 characters' using errcode = '22023';
  end if;

  select * into v_job
  from public.admin_catalog_deletion_jobs j
  where j.entity_type = 'subject'
    and j.entity_id = p_subject_id
    and j.status = 'prepared'
  for update;

  if found then
    return jsonb_build_object(
      'outcome', 'prepared',
      'job_id', v_job.id,
      'subject_id', v_job.entity_id,
      'storage_paths', to_jsonb(v_job.storage_paths),
      'dependency_counts', v_job.dependency_counts
    );
  end if;

  -- This is the first lock in every Subject-wide workflow.
  select * into v_subject
  from public.subjects s
  where s.id = p_subject_id
  for update;

  if not found then
    select * into v_job
    from public.admin_catalog_deletion_jobs j
    where j.entity_type = 'subject'
      and j.entity_id = p_subject_id
      and j.status = 'completed'
    order by j.completed_at desc
    limit 1
    for update;

    if found then
      return jsonb_build_object(
        'outcome', 'completed',
        'job_id', v_job.id,
        'subject_id', v_job.entity_id,
        'storage_paths', to_jsonb(v_job.storage_paths),
        'dependency_counts', v_job.dependency_counts
      );
    end if;

    return jsonb_build_object(
      'outcome', 'already_deleted',
      'subject_id', p_subject_id,
      'storage_paths', '[]'::jsonb,
      'dependency_counts', '{}'::jsonb
    );
  end if;

  -- A second Admin may have waited on the same Subject lock.
  select * into v_job
  from public.admin_catalog_deletion_jobs j
  where j.entity_type = 'subject'
    and j.entity_id = p_subject_id
    and j.status = 'prepared'
  for update;

  if found then
    return jsonb_build_object(
      'outcome', 'prepared',
      'job_id', v_job.id,
      'subject_id', v_job.entity_id,
      'storage_paths', to_jsonb(v_job.storage_paths),
      'dependency_counts', v_job.dependency_counts
    );
  end if;

  -- Post writers explicitly take KEY SHARE on this Community in their BEFORE
  -- trigger.  Whichever side gets the lock first determines a safe result.
  select c.id into v_community_id
  from public.communities c
  where c.subject_id = p_subject_id
  for update;

  if not found then
    raise exception 'The Subject Community is missing. Repair it before deleting this Subject.'
      using errcode = '55000';
  end if;

  if exists (
    select 1 from public.community_posts p where p.community_id = v_community_id
  ) then
    raise exception 'This Subject contains Community posts. Set it to inactive instead of deleting Student content.'
      using errcode = '55000';
  end if;

  -- Lock every child deterministically before path/count snapshots.  Upload RLS
  -- takes KEY SHARE on these same rows and material replacement takes row locks.
  perform m.id
  from public.subject_materials m
  where m.subject_id = p_subject_id
  order by m.id
  for update;

  if exists (
    select 1
    from public.admin_catalog_deletion_jobs j
    where j.entity_type = 'material'
      and j.subject_id = p_subject_id
      and j.status = 'prepared'
  ) then
    raise exception 'A PDF deletion is already in progress. Retry it before deleting the Subject.'
      using errcode = '55000';
  end if;

  select count(*)::integer into v_material_count
  from public.subject_materials m
  where m.subject_id = p_subject_id;

  select coalesce(array_agg(o.storage_path order by o.storage_path), array[]::text[]),
         count(*)::integer
  into v_paths, v_storage_object_count
  from public.subject_material_storage_objects o
  join public.subject_materials m on m.id = o.material_id
  where m.subject_id = p_subject_id;

  if exists (
    select 1
    from public.subject_materials m
    where m.subject_id = p_subject_id
      and not exists (
        select 1
        from public.subject_material_storage_objects o
        where o.material_id = m.id
          and o.subject_id = m.subject_id
          and o.storage_path = m.storage_path
      )
  ) then
    raise exception 'A PDF Storage path history is incomplete. Repair it before deletion.'
      using errcode = '55000';
  end if;

  select count(*)::integer into v_quiz_count
  from public.quizzes q
  where q.subject_id = p_subject_id
     or q.material_id in (
       select m.id from public.subject_materials m where m.subject_id = p_subject_id
     );

  -- Retiring takes row locks that serialize with attempt insertion.
  update public.quizzes q
  set status = 'retired'
  where q.status <> 'retired'
    and (
      q.subject_id = p_subject_id
      or q.material_id in (
        select m.id from public.subject_materials m where m.subject_id = p_subject_id
      )
    );

  select count(*)::integer into v_attempt_count
  from public.quiz_attempts qa
  where qa.subject_id = p_subject_id
     or qa.quiz_id in (
       select q.id
       from public.quizzes q
       where q.subject_id = p_subject_id
          or q.material_id in (
            select m.id from public.subject_materials m where m.subject_id = p_subject_id
          )
     );

  update public.subjects s
  set status = 'inactive'
  where s.id = p_subject_id;

  update public.subject_materials m
  set status = 'removed',
      removal_reason = v_reason,
      removed_at = now()
  where m.subject_id = p_subject_id and m.status <> 'removed';

  insert into public.admin_catalog_deletion_jobs (
    entity_type, entity_id, subject_id, requested_by, reason,
    storage_paths, dependency_counts
  ) values (
    'subject', p_subject_id, p_subject_id, v_admin_id, v_reason,
    v_paths,
    jsonb_build_object(
      'materials', v_material_count,
      'storage_objects', v_storage_object_count,
      'quizzes', v_quiz_count,
      'quiz_attempts', v_attempt_count,
      'community_posts', 0
    )
  )
  returning * into v_job;

  insert into public.admin_catalog_deletion_material_storage_objects (
    job_id, material_id, subject_id, storage_path
  )
  select v_job.id, o.material_id, o.subject_id, o.storage_path
  from public.subject_material_storage_objects o
  join public.subject_materials m on m.id = o.material_id
  where m.subject_id = p_subject_id
  order by o.material_id, o.storage_path;

  return jsonb_build_object(
    'outcome', 'prepared',
    'job_id', v_job.id,
    'subject_id', v_job.entity_id,
    'storage_paths', to_jsonb(v_job.storage_paths),
    'dependency_counts', v_job.dependency_counts
  );
end;
$$;

create or replace function public.admin_finalize_subject_deletion(
  p_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_job public.admin_catalog_deletion_jobs;
  v_community_id uuid;
  v_ledger_count integer := 0;
  v_ledger_material_count integer := 0;
  v_expected_materials integer := 0;
  v_expected_storage_objects integer := 0;
  v_preserved_quizzes integer := 0;
  v_preserved_attempts integer := 0;
  v_deleted_materials integer := 0;
  v_deleted_communities integer := 0;
  v_deleted_subjects integer := 0;
  v_verified_at timestamptz := now();
begin
  if v_admin_id is null or not public.is_admin() then
    raise exception 'An active Admin account is required' using errcode = '42501';
  end if;
  if p_job_id is null then
    raise exception 'A valid deletion job id is required' using errcode = '22023';
  end if;

  select * into v_job
  from public.admin_catalog_deletion_jobs j
  where j.id = p_job_id
  for update;

  if not found or v_job.entity_type <> 'subject' then
    raise exception 'Subject deletion job was not found' using errcode = 'P0002';
  end if;
  if v_job.status = 'completed' then
    return jsonb_build_object(
      'outcome', 'already_deleted',
      'job_id', v_job.id,
      'subject_id', v_job.entity_id,
      'deleted_subjects', 0,
      'deleted_materials', 0,
      'preserved_quizzes', coalesce((v_job.dependency_counts ->> 'quizzes')::integer, 0),
      'preserved_attempts', coalesce((v_job.dependency_counts ->> 'quiz_attempts')::integer, 0),
      'preserved_quiz_attempts', coalesce((v_job.dependency_counts ->> 'quiz_attempts')::integer, 0)
    );
  end if;

  v_expected_materials := coalesce((v_job.dependency_counts ->> 'materials')::integer, 0);
  v_expected_storage_objects := coalesce(
    (v_job.dependency_counts ->> 'storage_objects')::integer,
    -1
  );
  select count(*)::integer, count(distinct o.material_id)::integer
  into v_ledger_count, v_ledger_material_count
  from public.admin_catalog_deletion_material_storage_objects o
  where o.job_id = v_job.id;

  if v_ledger_count <> v_expected_storage_objects
    or v_ledger_material_count <> v_expected_materials
    or cardinality(v_job.storage_paths) <> v_ledger_count
    or exists (
      select 1
      from public.admin_catalog_deletion_material_storage_objects o
      where o.job_id = v_job.id
        and (
          o.subject_id <> v_job.entity_id
          or not (o.storage_path = any(v_job.storage_paths))
        )
    )
    or exists (
      select 1
      from public.admin_catalog_deletion_material_storage_objects o
      where o.job_id = v_job.id
        and not exists (
          select 1
          from public.subject_material_storage_objects so
          where so.material_id = o.material_id
            and so.subject_id = o.subject_id
            and so.storage_path = o.storage_path
        )
    )
    or exists (
      select 1
      from public.subject_material_storage_objects so
      join public.subject_materials m on m.id = so.material_id
      where m.subject_id = v_job.entity_id
        and not exists (
          select 1
          from public.admin_catalog_deletion_material_storage_objects o
          where o.job_id = v_job.id
            and o.material_id = so.material_id
            and o.subject_id = so.subject_id
            and o.storage_path = so.storage_path
        )
    )
  then
    raise exception 'The Subject deletion path ledger is incomplete'
      using errcode = '55000';
  end if;

  -- Lock the live rows again.  Missing rows are tolerated for idempotent repair,
  -- but any surviving row must still exactly match the prepared ledger.
  perform 1
  from public.subjects s
  where s.id = v_job.entity_id
  for update;

  select c.id into v_community_id
  from public.communities c
  where c.subject_id = v_job.entity_id
  for update;

  if v_community_id is not null and exists (
    select 1 from public.community_posts p where p.community_id = v_community_id
  ) then
    raise exception 'This Subject now contains Community posts and cannot be permanently deleted.'
      using errcode = '55000';
  end if;

  perform m.id
  from public.subject_materials m
  where m.subject_id = v_job.entity_id
  order by m.id
  for update;

  if exists (
    select 1
    from public.subject_materials m
    where m.subject_id = v_job.entity_id
      and (
        m.status <> 'removed'
        or not exists (
          select 1
          from public.admin_catalog_deletion_material_storage_objects o
          where o.job_id = v_job.id
            and o.material_id = m.id
            and o.subject_id = m.subject_id
            and o.storage_path = m.storage_path
        )
      )
  ) then
    raise exception 'The Subject materials changed during permanent deletion. Refresh and retry.'
      using errcode = '40001';
  end if;

  if exists (
    select 1
    from storage.objects so
    join public.admin_catalog_deletion_material_storage_objects o
      on o.storage_path = so.name and o.job_id = v_job.id
    where so.bucket_id = 'subject-materials'
  ) then
    raise exception 'One or more private PDF files are not deleted yet. Check the connection and retry.'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from public.quizzes q
    where q.status <> 'retired'
      and (
        q.subject_id = v_job.entity_id
        or q.material_id in (
          select o.material_id
          from public.admin_catalog_deletion_material_storage_objects o
          where o.job_id = v_job.id
        )
      )
  ) then
    raise exception 'A linked Quiz is still active. Retry deletion.' using errcode = '55000';
  end if;

  select count(*)::integer into v_preserved_quizzes
  from public.quizzes q
  where q.subject_id_snapshot = v_job.entity_id
     or q.material_id_snapshot in (
       select o.material_id
       from public.admin_catalog_deletion_material_storage_objects o
       where o.job_id = v_job.id
     );

  select count(*)::integer into v_preserved_attempts
  from public.quiz_attempts qa
  where qa.subject_id_snapshot = v_job.entity_id
     or qa.quiz_id in (
       select q.id
       from public.quizzes q
       where q.subject_id_snapshot = v_job.entity_id
          or q.material_id_snapshot in (
            select o.material_id
            from public.admin_catalog_deletion_material_storage_objects o
            where o.job_id = v_job.id
          )
     );

  update public.admin_catalog_deletion_material_storage_objects o
  set verified_absent_at = v_verified_at,
      verified_absent_by = v_admin_id
  where o.job_id = v_job.id;

  -- These deletes affect only the Admin catalog shell.  FK SET NULL preserves
  -- Quiz definitions/Attempts, and the Community RESTRICT key protects Posts.
  delete from public.subject_materials m
  where m.subject_id = v_job.entity_id;
  get diagnostics v_deleted_materials = row_count;

  delete from public.communities c
  where c.subject_id = v_job.entity_id;
  get diagnostics v_deleted_communities = row_count;

  delete from public.subjects s
  where s.id = v_job.entity_id;
  get diagnostics v_deleted_subjects = row_count;

  update public.admin_catalog_deletion_jobs j
  set status = 'completed',
      storage_verified_at = v_verified_at,
      storage_verified_by = v_admin_id,
      completed_at = v_verified_at,
      completed_by = v_admin_id
  where j.id = v_job.id;

  insert into public.admin_audit_log (
    actor_id, action, entity_type, entity_id, details
  ) values (
    v_admin_id,
    'permanently_delete_subject',
    'subject',
    v_job.entity_id,
    jsonb_build_object(
      'job_id', v_job.id,
      'reason', v_job.reason,
      'storage_paths', to_jsonb(v_job.storage_paths),
      'storage_verified_at', v_verified_at,
      'deleted_subjects', v_deleted_subjects,
      'deleted_communities', v_deleted_communities,
      'deleted_materials', v_deleted_materials,
      'preserved_quizzes', v_preserved_quizzes,
      'preserved_attempts', v_preserved_attempts,
      'preserved_quiz_attempts', v_preserved_attempts,
      'requested_by', v_job.requested_by
    )
  );

  return jsonb_build_object(
    'outcome', case when v_deleted_subjects = 0 then 'already_deleted' else 'deleted' end,
    'job_id', v_job.id,
    'subject_id', v_job.entity_id,
    'deleted_subjects', v_deleted_subjects,
    'deleted_communities', v_deleted_communities,
    'deleted_materials', v_deleted_materials,
    'preserved_quizzes', v_preserved_quizzes,
    'preserved_attempts', v_preserved_attempts,
    'preserved_quiz_attempts', v_preserved_attempts
  );
end;
$$;

-- A raw PostgREST DELETE must never bypass Storage proof or the Community
-- boundary.  The SECURITY DEFINER RPCs above are the only catalog delete path.
drop policy if exists subjects_admin_delete on public.subjects;
drop policy if exists subject_materials_admin_delete on public.subject_materials;
revoke delete on table public.subjects, public.subject_materials from authenticated;

-- Authenticated uploads are checked at the actual byte write, not when an
-- earlier signed token is minted.  UPDATE is tightened too, preventing an
-- approved object from being silently overwritten through Storage upsert.
drop policy if exists subject_materials_objects_insert on storage.objects;
create policy subject_materials_objects_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'subject-materials'
  and public.can_upload_subject_material_object(name)
);

drop policy if exists subject_materials_objects_update on storage.objects;
create policy subject_materials_objects_update on storage.objects
for update to authenticated
using (
  bucket_id = 'subject-materials'
  and public.can_upload_subject_material_object(name)
)
with check (
  bucket_id = 'subject-materials'
  and public.can_upload_subject_material_object(name)
);

drop policy if exists subject_materials_objects_delete on storage.objects;
create policy subject_materials_objects_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'subject-materials'
  and public.can_delete_subject_material_object(name)
);

-- Trigger helpers stay private.  Only the four narrow Admin RPCs and the two
-- boolean Storage-policy helpers are callable by authenticated sessions.
revoke execute on function public.enforce_quiz_catalog_context()
  from public, anon, authenticated;
revoke execute on function public.enforce_attempt_subject()
  from public, anon, authenticated;
revoke execute on function public.remember_subject_material_storage_object()
  from public, anon, authenticated;
revoke execute on function public.block_pending_catalog_deletion_mutation()
  from public, anon, authenticated;
revoke execute on function public.can_upload_subject_material_object(text)
  from public, anon, authenticated;
revoke execute on function public.can_delete_subject_material_object(text)
  from public, anon, authenticated;

revoke execute on function public.admin_prepare_material_deletion(uuid, integer, text)
  from public, anon, authenticated;
revoke execute on function public.admin_finalize_material_deletion(uuid)
  from public, anon, authenticated;
revoke execute on function public.admin_prepare_subject_deletion(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.admin_finalize_subject_deletion(uuid)
  from public, anon, authenticated;

grant execute on function public.admin_prepare_material_deletion(uuid, integer, text)
  to authenticated;
grant execute on function public.admin_finalize_material_deletion(uuid)
  to authenticated;
grant execute on function public.admin_prepare_subject_deletion(uuid, text)
  to authenticated;
grant execute on function public.admin_finalize_subject_deletion(uuid)
  to authenticated;
grant execute on function public.can_upload_subject_material_object(text)
  to authenticated;
grant execute on function public.can_delete_subject_material_object(text)
  to authenticated;

commit;
