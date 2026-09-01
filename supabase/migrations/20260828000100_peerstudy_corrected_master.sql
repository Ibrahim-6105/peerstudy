-- PeerStudy corrected-master Supabase schema.
--
-- This migration is deliberately self-contained and rerunnable. It creates the
-- relational model described by the corrected FYP, protects it with RLS, and
-- keeps public Student registration separate from trusted Admin operations.

begin;

-- gen_random_uuid() supplies opaque primary keys without a client sequence.
create extension if not exists pgcrypto;

-- A university account must use the one exact LIMU domain named by the FYP.
create or replace function public.is_limu_email(p_email text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_email is not null
    and lower(btrim(p_email)) ~ '^[^@[:space:]]+@limu[.]edu[.]ly$';
$$;

-- Profiles mirror Auth identities but never store passwords or access tokens.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  role text not null default 'student',
  status text not null default 'active',
  is_blocked boolean generated always as (status = 'restricted') stored,
  version integer not null default 1,
  restricted_at timestamptz,
  restricted_by uuid references public.profiles(id) on delete set null,
  restriction_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_full_name_check check (
    char_length(btrim(full_name)) between 2 and 100
    and full_name = btrim(full_name)
  ),
  constraint profiles_email_check check (
    email = lower(btrim(email)) and public.is_limu_email(email)
  ),
  constraint profiles_role_check check (role in ('student', 'admin')),
  constraint profiles_status_check check (status in ('active', 'restricted')),
  constraint profiles_version_check check (version >= 1),
  constraint profiles_restriction_check check (
    (status = 'active' and restricted_at is null and restriction_reason is null)
    or
    (status = 'restricted' and restricted_at is not null
      and char_length(btrim(restriction_reason)) between 5 and 500)
  )
);

-- The corrected master limits version one to one named School.
create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schools_name_check check (char_length(btrim(name)) between 2 and 160),
  constraint schools_status_check check (status in ('active', 'inactive'))
);

-- Academic Areas belong to exactly one School.
create table if not exists public.academic_areas (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  code text not null,
  name text not null,
  display_order integer not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint academic_areas_name_check check (char_length(btrim(name)) between 2 and 160),
  constraint academic_areas_code_check check (code in ('IT', 'ENGINEERING')),
  constraint academic_areas_display_order_check check (display_order >= 0),
  constraint academic_areas_status_check check (status in ('active', 'inactive')),
  constraint academic_areas_school_name_key unique (school_id, name),
  constraint academic_areas_school_code_key unique (school_id, code)
);

-- Departments cannot exist without their parent Academic Area.
create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  area_id uuid not null references public.academic_areas(id) on delete restrict,
  name text not null,
  description text not null default '',
  display_order integer not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint departments_name_check check (char_length(btrim(name)) between 2 and 160),
  constraint departments_description_check check (char_length(description) <= 1000),
  constraint departments_display_order_check check (display_order >= 0),
  constraint departments_status_check check (status in ('active', 'inactive')),
  constraint departments_area_name_key unique (area_id, name)
);

-- Subjects keep optional study-level metadata out of the required navigation.
create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments(id) on delete restrict,
  code text not null default '',
  name text not null,
  description text not null default '',
  study_level text,
  semester text,
  display_order integer not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subjects_code_check check (char_length(code) <= 40),
  constraint subjects_name_check check (char_length(btrim(name)) between 2 and 200),
  constraint subjects_description_check check (char_length(description) <= 2000),
  constraint subjects_study_level_check check (study_level is null or char_length(btrim(study_level)) between 1 and 80),
  constraint subjects_semester_check check (semester is null or char_length(btrim(semester)) between 1 and 80),
  constraint subjects_display_order_check check (display_order >= 0),
  constraint subjects_status_check check (status in ('active', 'inactive')),
  constraint subjects_department_name_key unique (department_id, name)
);

-- The Community primary key intentionally equals its Subject key. The unique
-- subject_id constraint independently documents the required one-to-one link.
create table if not exists public.communities (
  id uuid primary key,
  subject_id uuid not null unique references public.subjects(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint communities_same_id_check check (id = subject_id)
);

-- Only metadata is relational. PDF bytes stay in the private Storage bucket.
create table if not exists public.subject_materials (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete restrict,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  title text not null,
  summary text not null default '',
  storage_path text not null unique,
  mime_type text not null default 'application/pdf',
  size_bytes bigint not null,
  checksum text,
  status text not null default 'uploading',
  version integer not null default 1,
  display_order integer not null default 0,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  removal_reason text,
  removed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subject_materials_title_check check (char_length(btrim(title)) between 2 and 240),
  constraint subject_materials_summary_check check (char_length(summary) <= 2000),
  constraint subject_materials_path_check check (
    char_length(storage_path) between 5 and 1000
    and storage_path = btrim(storage_path)
    and storage_path not like '/%'
    and storage_path not like '%..%'
  ),
  constraint subject_materials_mime_check check (mime_type = 'application/pdf'),
  constraint subject_materials_size_check check (size_bytes between 1 and 26214400),
  constraint subject_materials_checksum_check check (
    checksum is null or checksum ~ '^[0-9a-f]{64}$'
  ),
  constraint subject_materials_status_check check (status in ('uploading', 'approved', 'removed')),
  constraint subject_materials_version_check check (version >= 1),
  constraint subject_materials_display_order_check check (display_order >= 0),
  constraint subject_materials_approval_check check (
    (status = 'approved' and approved_by is not null and approved_at is not null
      and checksum is not null)
    or status <> 'approved'
  ),
  constraint subject_materials_removal_check check (
    (status = 'removed' and removed_at is not null
      and char_length(btrim(removal_reason)) between 3 and 500)
    or
    (status <> 'removed' and removed_at is null and removal_reason is null)
  )
);

-- Posts are persistent Subject discussions. is_removed is generated from the
-- canonical status so API clients cannot make those two fields disagree.
create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete restrict,
  author_name text not null,
  body text not null,
  version integer not null default 1,
  status text not null default 'active',
  is_removed boolean generated always as (status = 'removed') stored,
  is_reported boolean not null default false,
  comment_count integer not null default 0,
  idempotency_key uuid not null,
  removal_reason text,
  removed_at timestamptz,
  removed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_posts_author_name_check check (char_length(btrim(author_name)) between 2 and 100),
  constraint community_posts_body_check check (char_length(btrim(body)) between 1 and 5000),
  constraint community_posts_version_check check (version >= 1),
  constraint community_posts_status_check check (status in ('active', 'removed')),
  constraint community_posts_comment_count_check check (comment_count >= 0),
  constraint community_posts_removal_check check (
    (status = 'active' and removed_at is null and removal_reason is null)
    or
    (status = 'removed' and removed_at is not null
      and char_length(btrim(removal_reason)) between 3 and 500)
  ),
  constraint community_posts_author_request_key unique (author_id, idempotency_key)
);

-- Comments are subordinate to exactly one Post.
create table if not exists public.community_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete restrict,
  author_name text not null,
  body text not null,
  version integer not null default 1,
  status text not null default 'active',
  is_removed boolean generated always as (status = 'removed') stored,
  idempotency_key uuid not null,
  removal_reason text,
  removed_at timestamptz,
  removed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_comments_author_name_check check (char_length(btrim(author_name)) between 2 and 100),
  constraint community_comments_body_check check (char_length(btrim(body)) between 1 and 2000),
  constraint community_comments_version_check check (version >= 1),
  constraint community_comments_status_check check (status in ('active', 'removed')),
  constraint community_comments_removal_check check (
    (status = 'active' and removed_at is null and removal_reason is null)
    or
    (status = 'removed' and removed_at is not null
      and char_length(btrim(removal_reason)) between 3 and 500)
  ),
  constraint community_comments_author_request_key unique (author_id, idempotency_key)
);

-- Validate the private AI payload before it may become an authoritative Quiz.
create or replace function public.is_valid_private_quiz_questions(p_questions jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p_questions) = 'array'
    and jsonb_array_length(p_questions) = 10
    and not exists (
      select 1
      from jsonb_array_elements(p_questions) as item(question)
      where jsonb_typeof(question) <> 'object'
        or not (question ?& array[
          'id', 'prompt', 'options', 'correct_index', 'explanation', 'source_page'
        ])
        or char_length(btrim(question ->> 'id')) not between 1 and 80
        or char_length(btrim(question ->> 'prompt')) not between 5 and 1000
        or jsonb_typeof(question -> 'options') <> 'array'
        or jsonb_array_length(question -> 'options') <> 4
        or exists (
          select 1
          from jsonb_array_elements(question -> 'options') as option(value)
          where jsonb_typeof(value) <> 'string'
            or char_length(btrim(value #>> '{}')) not between 1 and 500
        )
        or (
          select count(distinct lower(btrim(value #>> '{}')))
          from jsonb_array_elements(question -> 'options') as option(value)
        ) <> 4
        or coalesce(question ->> 'correct_index', '') !~ '^[0-3]$'
        or char_length(btrim(question ->> 'explanation')) not between 1 and 2000
        or coalesce(question ->> 'source_page', '') !~ '^[1-9][0-9]*$'
    );
$$;

-- A submitted answer array always contains one four-choice index per question.
create or replace function public.is_valid_quiz_answers(p_answers jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p_answers) = 'array'
    and jsonb_array_length(p_answers) = 10
    and not exists (
      select 1
      from jsonb_array_elements(p_answers) as answer(value)
      where jsonb_typeof(value) <> 'number'
        or (value #>> '{}') !~ '^[0-3]$'
    );
$$;

-- Correct answers remain in this client-denied table and are returned only by
-- the submit-quiz Edge Function after server scoring.
create table if not exists public.quizzes (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete restrict,
  material_id uuid not null references public.subject_materials(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  title text not null,
  questions jsonb not null,
  status text not null default 'ready',
  model_name text not null,
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  constraint quizzes_title_check check (char_length(btrim(title)) between 2 and 240),
  constraint quizzes_questions_check check (public.is_valid_private_quiz_questions(questions)),
  constraint quizzes_status_check check (status in ('ready', 'retired')),
  constraint quizzes_model_name_check check (char_length(btrim(model_name)) between 1 and 160),
  constraint quizzes_creator_request_key unique (created_by, idempotency_key)
);

-- An Attempt belongs to one Student and one already saved Quiz.
create table if not exists public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes(id) on delete restrict,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  student_id uuid not null references public.profiles(id) on delete restrict,
  answers jsonb not null,
  score integer not null,
  total integer not null default 10,
  corrections jsonb not null,
  status text not null default 'submitted',
  idempotency_key uuid not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz not null default now(),
  constraint quiz_attempts_answers_check check (public.is_valid_quiz_answers(answers)),
  constraint quiz_attempts_score_check check (total = 10 and score between 0 and total),
  constraint quiz_attempts_corrections_check check (
    jsonb_typeof(corrections) = 'array' and jsonb_array_length(corrections) = 10
  ),
  constraint quiz_attempts_status_check check (status = 'submitted'),
  constraint quiz_attempts_time_check check (completed_at >= started_at),
  constraint quiz_attempts_quiz_student_key unique (quiz_id, student_id),
  constraint quiz_attempts_student_request_key unique (student_id, idempotency_key)
);

-- A generated target_type keeps list queries simple while the check constraint
-- proves that a Report targets exactly one Post or one Comment.
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete restrict,
  post_id uuid references public.community_posts(id) on delete restrict,
  comment_id uuid references public.community_comments(id) on delete restrict,
  target_type text generated always as (
    case when post_id is not null then 'post' else 'comment' end
  ) stored,
  target_id uuid generated always as (coalesce(post_id, comment_id)) stored,
  reason text not null,
  details text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolution_note text,
  constraint reports_exactly_one_target_check check (
    (post_id is not null)::integer + (comment_id is not null)::integer = 1
  ),
  constraint reports_reason_check check (
    reason in ('harassment', 'misinformation', 'spam', 'inappropriate', 'copyright', 'other')
  ),
  constraint reports_details_check check (details is null or char_length(details) <= 1000),
  constraint reports_status_check check (
    status in ('pending', 'dismissed', 'content_removed', 'account_restricted')
  ),
  constraint reports_resolution_check check (
    (status = 'pending' and resolved_at is null and resolved_by is null and resolution_note is null)
    or
    (status <> 'pending' and resolved_at is not null and resolved_by is not null
      and char_length(btrim(resolution_note)) between 5 and 1000)
  )
);

-- Trusted RPCs append Admin actions here; clients cannot edit audit history.
create table if not exists public.admin_audit_log (
  id bigint generated by default as identity primary key,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint admin_audit_action_check check (char_length(btrim(action)) between 2 and 120),
  constraint admin_audit_entity_check check (char_length(btrim(entity_type)) between 2 and 80),
  constraint admin_audit_details_check check (jsonb_typeof(details) = 'object')
);

-- Keep common hierarchy, feed, moderation, and activity reads index-backed.
create index if not exists academic_areas_school_order_idx
  on public.academic_areas (school_id, status, display_order, name);
create index if not exists departments_area_order_idx
  on public.departments (area_id, status, display_order, name);
create index if not exists subjects_department_order_idx
  on public.subjects (department_id, status, display_order, name);
create unique index if not exists subjects_department_code_key
  on public.subjects (department_id, lower(code))
  where btrim(code) <> '';
create index if not exists subject_materials_subject_status_idx
  on public.subject_materials (subject_id, status, display_order, created_at desc);
create index if not exists community_posts_feed_idx
  on public.community_posts (community_id, status, created_at desc);
create index if not exists community_comments_thread_idx
  on public.community_comments (post_id, status, created_at asc);
create index if not exists quizzes_creator_created_idx
  on public.quizzes (created_by, created_at desc);
create index if not exists quiz_attempts_student_completed_idx
  on public.quiz_attempts (student_id, subject_id, completed_at desc);
create index if not exists reports_status_created_idx
  on public.reports (status, created_at asc);
create unique index if not exists reports_pending_post_reporter_key
  on public.reports (reporter_id, post_id)
  where post_id is not null and status = 'pending';
create unique index if not exists reports_pending_comment_reporter_key
  on public.reports (reporter_id, comment_id)
  where comment_id is not null and status = 'pending';
create index if not exists admin_audit_created_idx
  on public.admin_audit_log (created_at desc);

-- Apply one server timestamp consistently whenever mutable rows change.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create or replace function public.set_profile_updated_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.version := old.version + 1;
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_profile_updated_fields();

drop trigger if exists schools_set_updated_at on public.schools;
create trigger schools_set_updated_at
before update on public.schools
for each row execute function public.set_updated_at();

drop trigger if exists academic_areas_set_updated_at on public.academic_areas;
create trigger academic_areas_set_updated_at
before update on public.academic_areas
for each row execute function public.set_updated_at();

drop trigger if exists departments_set_updated_at on public.departments;
create trigger departments_set_updated_at
before update on public.departments
for each row execute function public.set_updated_at();

drop trigger if exists subjects_set_updated_at on public.subjects;
create trigger subjects_set_updated_at
before update on public.subjects
for each row execute function public.set_updated_at();

drop trigger if exists subject_materials_set_updated_at on public.subject_materials;
create trigger subject_materials_set_updated_at
before update on public.subject_materials
for each row execute function public.set_updated_at();

-- Material version changes once per visible catalog/content revision, not for
-- the checksum write or uploading-to-approved finalization of the same PDF.
create or replace function public.enforce_material_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.title := btrim(new.title);
  new.summary := btrim(new.summary);
  new.storage_path := btrim(new.storage_path);

  if tg_op = 'INSERT' then
    new.version := 1;
  else
    new.version := old.version;
    if new.storage_path is distinct from old.storage_path
      or new.title is distinct from old.title
      or new.summary is distinct from old.summary
      or new.display_order is distinct from old.display_order
      or (
        new.status is distinct from old.status
        and not (old.status = 'uploading' and new.status = 'approved')
      )
    then
      new.version := old.version + 1;
    end if;
  end if;

  if new.status = 'removed' then
    new.removal_reason := btrim(coalesce(new.removal_reason, ''));
    if tg_op = 'INSERT' or old.status <> 'removed' then
      new.removed_at := now();
    end if;
  else
    new.removal_reason := null;
    new.removed_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists subject_materials_enforce_lifecycle on public.subject_materials;
create trigger subject_materials_enforce_lifecycle
before insert or update on public.subject_materials
for each row execute function public.enforce_material_lifecycle();

drop trigger if exists community_posts_set_updated_at on public.community_posts;
create trigger community_posts_set_updated_at
before update on public.community_posts
for each row execute function public.set_updated_at();

drop trigger if exists community_comments_set_updated_at on public.community_comments;
create trigger community_comments_set_updated_at
before update on public.community_comments
for each row execute function public.set_updated_at();

-- Creating a Subject and its one Community is one PostgreSQL transaction. Any
-- Community failure aborts the Subject insert rather than leaving partial data.
create or replace function public.create_subject_community()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.communities (id, subject_id, created_at)
  values (new.id, new.id, new.created_at);
  return new;
end;
$$;

drop trigger if exists subjects_create_one_community on public.subjects;
create trigger subjects_create_one_community
after insert on public.subjects
for each row execute function public.create_subject_community();

-- Only the Comment trigger may maintain comment_count. This protects the
-- aggregate from direct Admin edits while still allowing nested trigger work.
create or replace function public.protect_post_comment_count()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.comment_count is distinct from old.comment_count and pg_trigger_depth() < 2 then
    raise exception 'comment_count is maintained by the database'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists community_posts_protect_comment_count on public.community_posts;
create trigger community_posts_protect_comment_count
before update of comment_count on public.community_posts
for each row execute function public.protect_post_comment_count();

-- Insert, removal, restoration, and defensive deletes keep the visible total
-- exact without trusting a phone-supplied number.
create or replace function public.sync_post_comment_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post_id uuid;
  v_delta integer := 0;
begin
  if tg_op = 'INSERT' then
    v_post_id := new.post_id;
    if new.status = 'active' then v_delta := 1; end if;
  elsif tg_op = 'DELETE' then
    v_post_id := old.post_id;
    if old.status = 'active' then v_delta := -1; end if;
  else
    if new.post_id <> old.post_id then
      raise exception 'A Comment cannot move to another Post'
        using errcode = '23514';
    end if;
    v_post_id := new.post_id;
    if old.status = 'active' and new.status <> 'active' then
      v_delta := -1;
    elsif old.status <> 'active' and new.status = 'active' then
      v_delta := 1;
    end if;
  end if;

  if v_delta <> 0 then
    update public.community_posts
    set comment_count = greatest(0, comment_count + v_delta)
    where id = v_post_id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists community_comments_sync_count on public.community_comments;
create trigger community_comments_sync_count
after insert or delete or update of status, post_id on public.community_comments
for each row execute function public.sync_post_comment_count();

-- subject_id is denormalized for fast Student history screens, while this
-- trigger proves it always equals the authoritative Quiz Subject.
create or replace function public.enforce_attempt_subject()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quiz_subject_id uuid;
begin
  select subject_id into v_quiz_subject_id
  from public.quizzes
  where id = new.quiz_id;
  if v_quiz_subject_id is null then
    raise exception 'Quiz was not found' using errcode = '23503';
  end if;
  if new.subject_id is distinct from v_quiz_subject_id then
    raise exception 'Attempt Subject must match Quiz Subject' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists quiz_attempts_enforce_subject on public.quiz_attempts;
create trigger quiz_attempts_enforce_subject
before insert or update of quiz_id, subject_id on public.quiz_attempts
for each row execute function public.enforce_attempt_subject();

-- Reject non-LIMU identities before Supabase Auth completes an insert or email
-- change. Password handling remains entirely inside Supabase Auth.
create or replace function public.enforce_limu_auth_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_limu_email(new.email) then
    raise exception 'PeerStudy requires a valid @limu.edu.ly email address'
      using errcode = '22023';
  end if;
  new.email := lower(btrim(new.email));
  return new;
end;
$$;

drop trigger if exists peerstudy_enforce_limu_email on auth.users;
create trigger peerstudy_enforce_limu_email
before insert or update of email on auth.users
for each row execute function public.enforce_limu_auth_email();

-- Public Auth signup can create only one active Student profile. Any `role`
-- supplied in user metadata is ignored rather than trusted.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_full_name text := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
begin
  if char_length(v_full_name) not between 2 and 100 then
    raise exception 'A full name containing 2-100 characters is required'
      using errcode = '22023';
  end if;

  insert into public.profiles (
    id, full_name, email, role, status, created_at, updated_at
  ) values (
    new.id, v_full_name, lower(btrim(new.email)), 'student', 'active', now(), now()
  );
  return new;
end;
$$;

drop trigger if exists peerstudy_create_student_profile on auth.users;
create trigger peerstudy_create_student_profile
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- A later verified Auth email change stays synchronized without changing role,
-- status, or the administrator-controlled profile lifecycle.
create or replace function public.sync_auth_user_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set email = lower(btrim(new.email))
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists peerstudy_sync_profile_email on auth.users;
create trigger peerstudy_sync_profile_email
after update of email on auth.users
for each row
when (old.email is distinct from new.email)
execute function public.sync_auth_user_email();

-- Security-definer helpers avoid recursive profile RLS checks. They expose only
-- booleans and never return email addresses or private profile rows.
create or replace function public.is_active_profile()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'active'
  );
$$;

create or replace function public.is_active_student()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'student' and status = 'active'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and status = 'active'
  );
$$;

-- Students may edit only their own display name. Role, status, email, and UUID
-- never come from this request; the profile trigger advances its version.
create or replace function public.update_my_full_name(p_full_name text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_full_name text := btrim(coalesce(p_full_name, ''));
  v_profile public.profiles;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required' using errcode = '42501';
  end if;
  if char_length(v_full_name) not between 2 and 100 then
    raise exception 'Full name must contain 2-100 characters' using errcode = '22023';
  end if;

  update public.profiles
  set full_name = v_full_name
  where id = v_user_id and role = 'student' and status = 'active'
  returning * into v_profile;
  if v_profile.id is null then
    raise exception 'Profile is unavailable' using errcode = 'P0002';
  end if;
  return v_profile;
end;
$$;

-- Centralize hierarchy visibility so RLS, RPCs, and Edge Functions agree on
-- what an active Student may use. Active Admins may inspect inactive catalog
-- rows while maintaining them.
create or replace function public.can_access_subject(p_subject_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when public.is_admin() then exists (
      select 1 from public.subjects where id = p_subject_id
    )
    when public.is_active_student() then exists (
      select 1
      from public.subjects s
      join public.departments d on d.id = s.department_id
      join public.academic_areas a on a.id = d.area_id
      join public.schools sc on sc.id = a.school_id
      where s.id = p_subject_id
        and s.status = 'active'
        and d.status = 'active'
        and a.status = 'active'
        and sc.status = 'active'
    )
    else false
  end;
$$;

-- Create a post from the authenticated Student identity. The name snapshot is
-- copied from the trusted profile, never accepted from a phone request.
create or replace function public.create_community_post(
  p_subject_id uuid,
  p_body text,
  p_idempotency_key uuid
)
returns public.community_posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_author_name text;
  v_community_id uuid;
  v_body text := btrim(coalesce(p_body, ''));
  v_post public.community_posts;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required' using errcode = '42501';
  end if;
  if p_subject_id is null or not public.can_access_subject(p_subject_id) then
    raise exception 'Subject is unavailable' using errcode = '42501';
  end if;
  if p_idempotency_key is null then
    raise exception 'idempotency_key is required' using errcode = '22023';
  end if;
  if char_length(v_body) not between 1 and 5000 then
    raise exception 'Post body must contain 1-5000 characters' using errcode = '22023';
  end if;

  select full_name into v_author_name
  from public.profiles
  where id = v_user_id and role = 'student' and status = 'active';

  select id into v_community_id
  from public.communities
  where subject_id = p_subject_id;
  if v_community_id is null then
    raise exception 'Subject Community is unavailable' using errcode = '23503';
  end if;

  insert into public.community_posts (
    community_id, author_id, author_name, body, idempotency_key
  ) values (
    v_community_id, v_user_id, v_author_name, v_body, p_idempotency_key
  )
  on conflict (author_id, idempotency_key) do nothing
  returning * into v_post;

  if v_post.id is null then
    select * into v_post
    from public.community_posts
    where author_id = v_user_id and idempotency_key = p_idempotency_key;
    if v_post.community_id <> v_community_id or v_post.body <> v_body then
      raise exception 'idempotency_key was already used for another post request'
        using errcode = '23505';
    end if;
  end if;

  return v_post;
end;
$$;

-- Version checks stop one device from silently overwriting a newer edit.
create or replace function public.update_community_post(
  p_post_id uuid,
  p_expected_version integer,
  p_body text
)
returns public.community_posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_body text := btrim(coalesce(p_body, ''));
  v_post public.community_posts;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required' using errcode = '42501';
  end if;
  if p_post_id is null or p_expected_version is null or p_expected_version < 1 then
    raise exception 'A post id and valid expected version are required' using errcode = '22023';
  end if;
  if char_length(v_body) not between 1 and 5000 then
    raise exception 'Post body must contain 1-5000 characters' using errcode = '22023';
  end if;

  select * into v_post
  from public.community_posts
  where id = p_post_id
  for update;
  if v_post.id is null then
    raise exception 'Post was not found' using errcode = 'P0002';
  end if;
  if v_post.author_id <> v_user_id then
    raise exception 'Only the post author may edit it' using errcode = '42501';
  end if;
  if v_post.status <> 'active' then
    raise exception 'A removed post cannot be edited' using errcode = '55000';
  end if;
  if not public.can_access_subject(v_post.community_id) then
    raise exception 'Subject is unavailable' using errcode = '42501';
  end if;
  if v_post.version <> p_expected_version then
    raise exception 'Post version conflict' using errcode = '40001';
  end if;

  update public.community_posts
  set body = v_body, version = version + 1
  where id = p_post_id
  returning * into v_post;
  return v_post;
end;
$$;

create or replace function public.delete_community_post(
  p_post_id uuid,
  p_expected_version integer,
  p_reason text default null
)
returns public.community_posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Removed by author');
  v_post public.community_posts;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required' using errcode = '42501';
  end if;
  if p_post_id is null or p_expected_version is null or p_expected_version < 1 then
    raise exception 'A post id and valid expected version are required' using errcode = '22023';
  end if;
  if char_length(v_reason) not between 3 and 500 then
    raise exception 'Removal reason must contain 3-500 characters' using errcode = '22023';
  end if;

  select * into v_post
  from public.community_posts
  where id = p_post_id
  for update;
  if v_post.id is null then
    raise exception 'Post was not found' using errcode = 'P0002';
  end if;
  if v_post.author_id <> v_user_id then
    raise exception 'Only the post author may remove it' using errcode = '42501';
  end if;
  if v_post.status <> 'active' then
    raise exception 'Post is already removed' using errcode = '55000';
  end if;
  if v_post.version <> p_expected_version then
    raise exception 'Post version conflict' using errcode = '40001';
  end if;

  update public.community_posts
  set status = 'removed', version = version + 1,
      removal_reason = v_reason, removed_at = now(), removed_by = v_user_id
  where id = p_post_id
  returning * into v_post;
  return v_post;
end;
$$;

create or replace function public.create_community_comment(
  p_subject_id uuid,
  p_post_id uuid,
  p_body text,
  p_idempotency_key uuid
)
returns public.community_comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_author_name text;
  v_body text := btrim(coalesce(p_body, ''));
  v_post public.community_posts;
  v_comment public.community_comments;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required' using errcode = '42501';
  end if;
  if p_subject_id is null or not public.can_access_subject(p_subject_id) then
    raise exception 'Subject is unavailable' using errcode = '42501';
  end if;
  if p_post_id is null or p_idempotency_key is null then
    raise exception 'post_id and idempotency_key are required' using errcode = '22023';
  end if;
  if char_length(v_body) not between 1 and 2000 then
    raise exception 'Comment body must contain 1-2000 characters' using errcode = '22023';
  end if;

  select p.* into v_post
  from public.community_posts p
  join public.communities c on c.id = p.community_id
  where p.id = p_post_id and c.subject_id = p_subject_id
  for update of p;
  if v_post.id is null or v_post.status <> 'active' then
    raise exception 'Post is unavailable' using errcode = 'P0002';
  end if;

  select full_name into v_author_name
  from public.profiles
  where id = v_user_id and role = 'student' and status = 'active';

  insert into public.community_comments (
    post_id, author_id, author_name, body, idempotency_key
  ) values (
    p_post_id, v_user_id, v_author_name, v_body, p_idempotency_key
  )
  on conflict (author_id, idempotency_key) do nothing
  returning * into v_comment;

  if v_comment.id is null then
    select * into v_comment
    from public.community_comments
    where author_id = v_user_id and idempotency_key = p_idempotency_key;
    if v_comment.post_id <> p_post_id or v_comment.body <> v_body then
      raise exception 'idempotency_key was already used for another comment request'
        using errcode = '23505';
    end if;
  end if;

  return v_comment;
end;
$$;

create or replace function public.update_community_comment(
  p_comment_id uuid,
  p_expected_version integer,
  p_body text
)
returns public.community_comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_subject_id uuid;
  v_body text := btrim(coalesce(p_body, ''));
  v_comment public.community_comments;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required' using errcode = '42501';
  end if;
  if p_comment_id is null or p_expected_version is null or p_expected_version < 1 then
    raise exception 'A comment id and valid expected version are required' using errcode = '22023';
  end if;
  if char_length(v_body) not between 1 and 2000 then
    raise exception 'Comment body must contain 1-2000 characters' using errcode = '22023';
  end if;

  select cc.* into v_comment
  from public.community_comments cc
  where cc.id = p_comment_id
  for update of cc;
  if v_comment.id is null then
    raise exception 'Comment was not found' using errcode = 'P0002';
  end if;
  select c.subject_id into v_subject_id
  from public.community_posts p
  join public.communities c on c.id = p.community_id
  where p.id = v_comment.post_id;
  if v_comment.author_id <> v_user_id then
    raise exception 'Only the comment author may edit it' using errcode = '42501';
  end if;
  if v_comment.status <> 'active' then
    raise exception 'A removed comment cannot be edited' using errcode = '55000';
  end if;
  if not public.can_access_subject(v_subject_id) then
    raise exception 'Subject is unavailable' using errcode = '42501';
  end if;
  if v_comment.version <> p_expected_version then
    raise exception 'Comment version conflict' using errcode = '40001';
  end if;

  update public.community_comments
  set body = v_body, version = version + 1
  where id = p_comment_id
  returning * into v_comment;
  return v_comment;
end;
$$;

create or replace function public.delete_community_comment(
  p_comment_id uuid,
  p_expected_version integer,
  p_reason text default null
)
returns public.community_comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Removed by author');
  v_comment public.community_comments;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required' using errcode = '42501';
  end if;
  if p_comment_id is null or p_expected_version is null or p_expected_version < 1 then
    raise exception 'A comment id and valid expected version are required' using errcode = '22023';
  end if;
  if char_length(v_reason) not between 3 and 500 then
    raise exception 'Removal reason must contain 3-500 characters' using errcode = '22023';
  end if;

  select * into v_comment
  from public.community_comments
  where id = p_comment_id
  for update;
  if v_comment.id is null then
    raise exception 'Comment was not found' using errcode = 'P0002';
  end if;
  if v_comment.author_id <> v_user_id then
    raise exception 'Only the comment author may remove it' using errcode = '42501';
  end if;
  if v_comment.status <> 'active' then
    raise exception 'Comment is already removed' using errcode = '55000';
  end if;
  if v_comment.version <> p_expected_version then
    raise exception 'Comment version conflict' using errcode = '40001';
  end if;

  update public.community_comments
  set status = 'removed', version = version + 1,
      removal_reason = v_reason, removed_at = now(), removed_by = v_user_id
  where id = p_comment_id
  returning * into v_comment;
  return v_comment;
end;
$$;

-- A Student may create at most one pending report for the same target. For a
-- Comment, parent_id is checked when supplied and otherwise derived safely.
create or replace function public.create_content_report(
  p_subject_id uuid,
  p_target_type text,
  p_target_id uuid,
  p_parent_id uuid default null,
  p_reason text default null,
  p_details text default null
)
returns public.reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_target_type text := lower(btrim(coalesce(p_target_type, '')));
  v_reason text := lower(btrim(coalesce(p_reason, '')));
  v_details text := nullif(btrim(coalesce(p_details, '')), '');
  v_target_author uuid;
  v_post_id uuid;
  v_report public.reports;
begin
  if v_user_id is null or not public.is_active_student() then
    raise exception 'An active Student account is required' using errcode = '42501';
  end if;
  if p_subject_id is null or not public.can_access_subject(p_subject_id) then
    raise exception 'Subject is unavailable' using errcode = '42501';
  end if;
  if p_target_id is null or v_target_type not in ('post', 'comment') then
    raise exception 'A valid report target is required' using errcode = '22023';
  end if;
  if v_reason not in (
    'harassment', 'misinformation', 'spam', 'inappropriate', 'copyright', 'other'
  ) then
    raise exception 'Invalid report reason' using errcode = '22023';
  end if;
  if v_details is not null and char_length(v_details) > 1000 then
    raise exception 'Report details cannot exceed 1000 characters' using errcode = '22023';
  end if;

  if v_target_type = 'post' then
    if p_parent_id is not null then
      raise exception 'parent_id must be null for a post report' using errcode = '22023';
    end if;
    select p.author_id, p.id into v_target_author, v_post_id
    from public.community_posts p
    join public.communities c on c.id = p.community_id
    where p.id = p_target_id
      and c.subject_id = p_subject_id
      and p.status = 'active';
  else
    select cc.author_id, p.id into v_target_author, v_post_id
    from public.community_comments cc
    join public.community_posts p on p.id = cc.post_id
    join public.communities c on c.id = p.community_id
    where cc.id = p_target_id
      and c.subject_id = p_subject_id
      and cc.status = 'active'
      and p.status = 'active';
    if p_parent_id is not null and p_parent_id <> v_post_id then
      raise exception 'parent_id does not match the Comment Post' using errcode = '22023';
    end if;
  end if;

  if v_target_author is null then
    raise exception 'Report target is unavailable' using errcode = 'P0002';
  end if;
  if v_target_author = v_user_id then
    raise exception 'Students cannot report their own content' using errcode = '22023';
  end if;

  begin
    if v_target_type = 'post' then
      insert into public.reports (reporter_id, post_id, reason, details)
      values (v_user_id, p_target_id, v_reason, v_details)
      returning * into v_report;
    else
      insert into public.reports (reporter_id, comment_id, reason, details)
      values (v_user_id, p_target_id, v_reason, v_details)
      returning * into v_report;
    end if;
  exception when unique_violation then
    if v_target_type = 'post' then
      select * into v_report from public.reports
      where reporter_id = v_user_id and post_id = p_target_id and status = 'pending';
    else
      select * into v_report from public.reports
      where reporter_id = v_user_id and comment_id = p_target_id and status = 'pending';
    end if;
  end;

  if v_report.id is null then
    raise exception 'The report could not be saved' using errcode = '40001';
  end if;

  update public.community_posts set is_reported = true where id = v_post_id;
  return v_report;
end;
$$;

-- Resolve one pending report and its optional moderation action atomically.
-- No client can mark a Report resolved without completing the chosen action.
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

  select * into v_report
  from public.reports
  where id = p_report_id
  for update;
  if v_report.id is null then
    raise exception 'Report was not found' using errcode = 'P0002';
  end if;
  if v_report.status <> 'pending' then
    raise exception 'Report was already resolved' using errcode = '55000';
  end if;

  if v_report.post_id is not null then
    v_post_id := v_report.post_id;
    select author_id into v_target_author
    from public.community_posts where id = v_report.post_id;
  else
    select p.id, cc.author_id into v_post_id, v_target_author
    from public.community_comments cc
    join public.community_posts p on p.id = cc.post_id
    where cc.id = v_report.comment_id;
  end if;
  if v_target_author is null then
    raise exception 'Report target no longer exists' using errcode = 'P0002';
  end if;

  if v_action = 'dismiss' then
    v_new_status := 'dismissed';
  elsif v_action = 'remove' then
    if v_report.post_id is not null then
      update public.community_posts
      set status = 'removed', version = version + 1,
          removal_reason = left(v_note, 500), removed_at = now(), removed_by = v_admin_id
      where id = v_report.post_id and status = 'active';
    else
      update public.community_comments
      set status = 'removed', version = version + 1,
          removal_reason = left(v_note, 500), removed_at = now(), removed_by = v_admin_id
      where id = v_report.comment_id and status = 'active';
    end if;
    v_new_status := 'content_removed';
  else
    select role into v_target_role from public.profiles where id = v_target_author for update;
    if v_target_author = v_admin_id or v_target_role <> 'student' then
      raise exception 'Admin accounts cannot be restricted through a content report'
        using errcode = '42501';
    end if;
    update public.profiles
    set status = 'restricted', restricted_at = now(), restricted_by = v_admin_id,
        restriction_reason = left(v_note, 500)
    where id = v_target_author;
    v_new_status := 'account_restricted';
  end if;

  update public.reports
  set status = v_new_status, resolved_at = now(), resolved_by = v_admin_id,
      resolution_note = v_note
  where id = p_report_id
  returning * into v_report;

  update public.community_posts p
  set is_reported = exists (
    select 1
    from public.reports r
    where r.status = 'pending'
      and (r.post_id = p.id or r.comment_id in (
        select cc.id from public.community_comments cc where cc.post_id = p.id
      ))
  )
  where p.id = v_post_id;

  insert into public.admin_audit_log (
    actor_id, action, entity_type, entity_id, details
  ) values (
    v_admin_id, 'resolve_report_' || v_action, 'report', p_report_id,
    jsonb_build_object('target_type', v_report.target_type, 'target_id', v_report.target_id)
  );
  return v_report;
end;
$$;

create or replace function public.admin_set_user_status(
  p_profile_id uuid,
  p_status text,
  p_reason text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_profile public.profiles;
begin
  if v_admin_id is null or not public.is_admin() then
    raise exception 'An active Admin account is required' using errcode = '42501';
  end if;
  if p_profile_id is null or v_status not in ('active', 'restricted') then
    raise exception 'A valid profile id and status are required' using errcode = '22023';
  end if;
  if p_profile_id = v_admin_id then
    raise exception 'Admins cannot change their own status' using errcode = '42501';
  end if;
  if v_status = 'restricted' and (
    v_reason is null or char_length(v_reason) not between 5 and 500
  ) then
    raise exception 'Restriction reason must contain 5-500 characters' using errcode = '22023';
  end if;

  select * into v_profile from public.profiles where id = p_profile_id for update;
  if v_profile.id is null then
    raise exception 'Profile was not found' using errcode = 'P0002';
  end if;
  if v_profile.role <> 'student' then
    raise exception 'Only Student account status can be changed here' using errcode = '42501';
  end if;

  update public.profiles
  set status = v_status,
      restricted_at = case when v_status = 'restricted' then now() else null end,
      restricted_by = case when v_status = 'restricted' then v_admin_id else null end,
      restriction_reason = case when v_status = 'restricted' then v_reason else null end
  where id = p_profile_id
  returning * into v_profile;

  insert into public.admin_audit_log (
    actor_id, action, entity_type, entity_id, details
  ) values (
    v_admin_id, 'set_user_' || v_status, 'profile', p_profile_id,
    jsonb_build_object('reason', v_reason)
  );
  return v_profile;
end;
$$;

-- The trigger and this RPC share the same transaction, so a Subject is never
-- returned without its exactly-one Community.
create or replace function public.admin_create_subject_with_community(
  p_department_id uuid,
  p_name text,
  p_code text default '',
  p_description text default '',
  p_study_level text default null,
  p_semester text default null,
  p_display_order integer default 0,
  p_status text default 'active'
)
returns table (subject_id uuid, community_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_subject_id uuid;
  v_community_id uuid;
begin
  if v_admin_id is null or not public.is_admin() then
    raise exception 'An active Admin account is required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.departments where id = p_department_id) then
    raise exception 'Department was not found' using errcode = '23503';
  end if;
  if lower(btrim(coalesce(p_status, ''))) not in ('active', 'inactive') then
    raise exception 'Subject status must be active or inactive' using errcode = '22023';
  end if;

  insert into public.subjects (
    department_id, code, name, description, study_level, semester,
    display_order, status
  ) values (
    p_department_id, btrim(coalesce(p_code, '')), btrim(coalesce(p_name, '')),
    btrim(coalesce(p_description, '')), nullif(btrim(coalesce(p_study_level, '')), ''),
    nullif(btrim(coalesce(p_semester, '')), ''), coalesce(p_display_order, 0),
    lower(btrim(coalesce(p_status, 'active')))
  ) returning id into v_subject_id;

  select c.id into v_community_id
  from public.communities c where c.subject_id = v_subject_id;
  if v_community_id is null then
    raise exception 'Community creation failed' using errcode = '23503';
  end if;

  insert into public.admin_audit_log (
    actor_id, action, entity_type, entity_id, details
  ) values (
    v_admin_id, 'create_subject', 'subject', v_subject_id,
    jsonb_build_object('department_id', p_department_id, 'community_id', v_community_id)
  );
  return query select v_subject_id, v_community_id;
end;
$$;

-- Every client-facing table uses RLS. Edge Functions use the service role only
-- after validating the caller; phones receive only the narrow grants below.
alter table public.profiles enable row level security;
alter table public.schools enable row level security;
alter table public.academic_areas enable row level security;
alter table public.departments enable row level security;
alter table public.subjects enable row level security;
alter table public.communities enable row level security;
alter table public.subject_materials enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.reports enable row level security;
alter table public.admin_audit_log enable row level security;

drop policy if exists profiles_read_self_or_admin on public.profiles;
create policy profiles_read_self_or_admin on public.profiles
for select to authenticated
using (id = auth.uid() or public.is_admin());

drop policy if exists schools_read on public.schools;
create policy schools_read on public.schools
for select to authenticated
using (public.is_admin() or (public.is_active_student() and status = 'active'));
drop policy if exists schools_admin_insert on public.schools;
create policy schools_admin_insert on public.schools
for insert to authenticated with check (public.is_admin());
drop policy if exists schools_admin_update on public.schools;
create policy schools_admin_update on public.schools
for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists schools_admin_delete on public.schools;
create policy schools_admin_delete on public.schools
for delete to authenticated using (public.is_admin());

drop policy if exists academic_areas_read on public.academic_areas;
create policy academic_areas_read on public.academic_areas
for select to authenticated
using (
  public.is_admin()
  or (
    public.is_active_student() and status = 'active'
    and exists (
      select 1 from public.schools sc where sc.id = school_id and sc.status = 'active'
    )
  )
);
drop policy if exists academic_areas_admin_insert on public.academic_areas;
create policy academic_areas_admin_insert on public.academic_areas
for insert to authenticated with check (public.is_admin());
drop policy if exists academic_areas_admin_update on public.academic_areas;
create policy academic_areas_admin_update on public.academic_areas
for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists academic_areas_admin_delete on public.academic_areas;
create policy academic_areas_admin_delete on public.academic_areas
for delete to authenticated using (public.is_admin());

drop policy if exists departments_read on public.departments;
create policy departments_read on public.departments
for select to authenticated
using (
  public.is_admin()
  or (
    public.is_active_student() and status = 'active'
    and exists (
      select 1
      from public.academic_areas a
      join public.schools sc on sc.id = a.school_id
      where a.id = area_id and a.status = 'active' and sc.status = 'active'
    )
  )
);
drop policy if exists departments_admin_insert on public.departments;
create policy departments_admin_insert on public.departments
for insert to authenticated with check (public.is_admin());
drop policy if exists departments_admin_update on public.departments;
create policy departments_admin_update on public.departments
for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists departments_admin_delete on public.departments;
create policy departments_admin_delete on public.departments
for delete to authenticated using (public.is_admin());

drop policy if exists subjects_read on public.subjects;
create policy subjects_read on public.subjects
for select to authenticated
using (public.can_access_subject(id));
drop policy if exists subjects_admin_insert on public.subjects;
create policy subjects_admin_insert on public.subjects
for insert to authenticated with check (public.is_admin());
drop policy if exists subjects_admin_update on public.subjects;
create policy subjects_admin_update on public.subjects
for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists subjects_admin_delete on public.subjects;
create policy subjects_admin_delete on public.subjects
for delete to authenticated using (public.is_admin());

drop policy if exists communities_read on public.communities;
create policy communities_read on public.communities
for select to authenticated
using (public.can_access_subject(subject_id));

drop policy if exists subject_materials_read on public.subject_materials;
create policy subject_materials_read on public.subject_materials
for select to authenticated
using (
  public.is_admin()
  or (status = 'approved' and public.can_access_subject(subject_id))
);
drop policy if exists subject_materials_admin_insert on public.subject_materials;
create policy subject_materials_admin_insert on public.subject_materials
for insert to authenticated
with check (public.is_admin() and uploaded_by = auth.uid());
drop policy if exists subject_materials_admin_update on public.subject_materials;
create policy subject_materials_admin_update on public.subject_materials
for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists subject_materials_admin_delete on public.subject_materials;
create policy subject_materials_admin_delete on public.subject_materials
for delete to authenticated using (public.is_admin());

drop policy if exists community_posts_read on public.community_posts;
create policy community_posts_read on public.community_posts
for select to authenticated
using (
  public.is_admin()
  or (
    public.is_active_student() and status = 'active'
    and public.can_access_subject(community_id)
  )
);

drop policy if exists community_comments_read on public.community_comments;
create policy community_comments_read on public.community_comments
for select to authenticated
using (
  public.is_admin()
  or (
    public.is_active_student() and status = 'active'
    and exists (
      select 1
      from public.community_posts p
      join public.communities c on c.id = p.community_id
      where p.id = post_id and p.status = 'active'
        and public.can_access_subject(c.subject_id)
    )
  )
);

drop policy if exists quizzes_admin_read on public.quizzes;
create policy quizzes_admin_read on public.quizzes
for select to authenticated using (public.is_admin());

drop policy if exists quiz_attempts_read_own_or_admin on public.quiz_attempts;
create policy quiz_attempts_read_own_or_admin on public.quiz_attempts
for select to authenticated
using (public.is_admin() or (student_id = auth.uid() and public.is_active_student()));

drop policy if exists reports_read_own_or_admin on public.reports;
create policy reports_read_own_or_admin on public.reports
for select to authenticated
using (public.is_admin() or (reporter_id = auth.uid() and public.is_active_student()));

drop policy if exists admin_audit_read on public.admin_audit_log;
create policy admin_audit_read on public.admin_audit_log
for select to authenticated using (public.is_admin());

-- Remove PostgREST's broad defaults, then grant only operations with explicit
-- RLS policies. Community/report writes and quiz scoring remain RPC/Edge-only.
revoke all on table
  public.profiles, public.schools, public.academic_areas, public.departments,
  public.subjects, public.communities, public.subject_materials,
  public.community_posts, public.community_comments, public.quizzes,
  public.quiz_attempts, public.reports, public.admin_audit_log
from anon, authenticated;

grant select on table
  public.profiles, public.schools, public.academic_areas, public.departments,
  public.subjects, public.communities, public.subject_materials,
  public.community_posts, public.community_comments, public.quizzes,
  public.quiz_attempts, public.reports, public.admin_audit_log
to authenticated;

grant insert, update, delete on table
  public.schools, public.academic_areas, public.departments, public.subjects,
  public.subject_materials
to authenticated;

-- Functions are closed by default and opened only to the role that needs each
-- API. Trigger/check functions do not need direct client EXECUTE permission.
revoke execute on function public.is_limu_email(text) from public, anon, authenticated;
revoke execute on function public.is_valid_private_quiz_questions(jsonb) from public, anon, authenticated;
revoke execute on function public.is_valid_quiz_answers(jsonb) from public, anon, authenticated;
revoke execute on function public.is_active_profile() from public, anon, authenticated;
revoke execute on function public.is_active_student() from public, anon, authenticated;
revoke execute on function public.is_admin() from public, anon, authenticated;
revoke execute on function public.can_access_subject(uuid) from public, anon, authenticated;
revoke execute on function public.update_my_full_name(text) from public, anon, authenticated;
revoke execute on function public.create_community_post(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.update_community_post(uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.delete_community_post(uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.create_community_comment(uuid, uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.update_community_comment(uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.delete_community_comment(uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.create_content_report(uuid, text, uuid, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.admin_resolve_report(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.admin_set_user_status(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.admin_create_subject_with_community(uuid, text, text, text, text, text, integer, text) from public, anon, authenticated;

grant execute on function public.is_active_profile() to authenticated;
grant execute on function public.is_active_student() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_access_subject(uuid) to authenticated;
grant execute on function public.update_my_full_name(text) to authenticated;
grant execute on function public.create_community_post(uuid, text, uuid) to authenticated;
grant execute on function public.update_community_post(uuid, integer, text) to authenticated;
grant execute on function public.delete_community_post(uuid, integer, text) to authenticated;
grant execute on function public.create_community_comment(uuid, uuid, text, uuid) to authenticated;
grant execute on function public.update_community_comment(uuid, integer, text) to authenticated;
grant execute on function public.delete_community_comment(uuid, integer, text) to authenticated;
grant execute on function public.create_content_report(uuid, text, uuid, uuid, text, text) to authenticated;
grant execute on function public.admin_resolve_report(uuid, text, text) to authenticated;
grant execute on function public.admin_set_user_status(uuid, text, text) to authenticated;
grant execute on function public.admin_create_subject_with_community(uuid, text, text, text, text, text, integer, text) to authenticated;

-- The PDF bucket is private. Students can download only an approved Material
-- whose subject is currently accessible; only active Admins mutate objects.
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'subject-materials', 'subject-materials', false, 26214400,
  array['application/pdf']::text[]
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists subject_materials_objects_read on storage.objects;
create policy subject_materials_objects_read on storage.objects
for select to authenticated
using (
  bucket_id = 'subject-materials'
  and (
    public.is_admin()
    or exists (
      select 1
      from public.subject_materials m
      where m.storage_path = name
        and m.status = 'approved'
        and public.can_access_subject(m.subject_id)
    )
  )
);

drop policy if exists subject_materials_objects_insert on storage.objects;
create policy subject_materials_objects_insert on storage.objects
for insert to authenticated
with check (bucket_id = 'subject-materials' and public.is_admin());

drop policy if exists subject_materials_objects_update on storage.objects;
create policy subject_materials_objects_update on storage.objects
for update to authenticated
using (bucket_id = 'subject-materials' and public.is_admin())
with check (bucket_id = 'subject-materials' and public.is_admin());

drop policy if exists subject_materials_objects_delete on storage.objects;
create policy subject_materials_objects_delete on storage.objects
for delete to authenticated
using (bucket_id = 'subject-materials' and public.is_admin());

-- Realtime publishes both feeds. Primary-key identity is required on PostgreSQL
-- 17 because FULL identity cannot include the stored generated is_removed field.
alter table public.community_posts replica identity default;
alter table public.community_comments replica identity default;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'community_posts'
    ) then
      execute 'alter publication supabase_realtime add table public.community_posts';
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'community_comments'
    ) then
      execute 'alter publication supabase_realtime add table public.community_comments';
    end if;
  end if;
end;
$$;

commit;
