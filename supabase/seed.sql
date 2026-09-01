-- PeerStudy corrected-master reference data.
--
-- This seed deliberately creates no Auth users, profiles, posts, materials,
-- quizzes, attempts, or reports. Accounts are created fresh through Supabase
-- Auth (Admin bootstrap is documented separately), and uploaded PDFs must be
-- real files. Only names explicitly present in the corrected FYP are seeded.

begin;

do $$
declare
  v_school_id uuid;
  v_it_area_id uuid;
  v_engineering_area_id uuid;
  v_software_department_id uuid;
begin
  insert into public.schools (id, name, status)
  values (
    '10000000-0000-4000-8000-000000000001',
    'School of Technology and Engineering',
    'active'
  )
  on conflict (name) do update set status = excluded.status
  returning id into v_school_id;

  insert into public.academic_areas (
    id, school_id, code, name, display_order, status
  ) values (
    '11000000-0000-4000-8000-000000000001',
    v_school_id,
    'IT',
    'Information Technology',
    1,
    'active'
  )
  on conflict (school_id, code) do update
  set name = excluded.name,
      display_order = excluded.display_order,
      status = excluded.status
  returning id into v_it_area_id;

  insert into public.academic_areas (
    id, school_id, code, name, display_order, status
  ) values (
    '12000000-0000-4000-8000-000000000001',
    v_school_id,
    'ENGINEERING',
    'Engineering',
    2,
    'active'
  )
  on conflict (school_id, code) do update
  set name = excluded.name,
      display_order = excluded.display_order,
      status = excluded.status
  returning id into v_engineering_area_id;

  insert into public.departments (
    id, area_id, name, description, display_order, status
  ) values
    (
      '21000000-0000-4000-8000-000000000001', v_it_area_id,
      'Software Engineering', '', 1, 'active'
    ),
    (
      '22000000-0000-4000-8000-000000000001', v_it_area_id,
      'Network', '', 2, 'active'
    ),
    (
      '23000000-0000-4000-8000-000000000001', v_it_area_id,
      'Telecommunications', '', 3, 'active'
    ),
    (
      '24000000-0000-4000-8000-000000000001', v_it_area_id,
      'Health Informatics', '', 4, 'active'
    ),
    (
      '25000000-0000-4000-8000-000000000001', v_it_area_id,
      'Artificial Intelligence (AI)', '', 5, 'active'
    )
  on conflict (area_id, name) do update
  set description = excluded.description,
      display_order = excluded.display_order,
      status = excluded.status;

  insert into public.departments (
    id, area_id, name, description, display_order, status
  ) values
    (
      '26000000-0000-4000-8000-000000000001', v_engineering_area_id,
      'Architectural and Structural Engineering', '', 1, 'active'
    ),
    (
      '27000000-0000-4000-8000-000000000001', v_engineering_area_id,
      'Mechatronics', '', 2, 'active'
    ),
    (
      '28000000-0000-4000-8000-000000000001', v_engineering_area_id,
      'Interior Design', '', 3, 'active'
    )
  on conflict (area_id, name) do update
  set description = excluded.description,
      display_order = excluded.display_order,
      status = excluded.status;

  select id into strict v_software_department_id
  from public.departments
  where area_id = v_it_area_id and name = 'Software Engineering';

  -- The corrected document explicitly shows this one Subject. Additional real
  -- Subject rows are entered by an Admin through the same schema after review.
  insert into public.subjects (
    id, department_id, code, name, description, study_level, semester,
    display_order, status
  ) values (
    '31000000-0000-4000-8000-000000000001',
    v_software_department_id,
    '',
    'Software Engineering Fundamentals',
    '',
    null,
    null,
    1,
    'active'
  )
  on conflict (department_id, name) do update
  set code = excluded.code,
      description = excluded.description,
      study_level = excluded.study_level,
      semester = excluded.semester,
      display_order = excluded.display_order,
      status = excluded.status;

  -- Defensive repair for a database imported from before the Subject trigger.
  insert into public.communities (id, subject_id)
  select s.id, s.id
  from public.subjects s
  where s.department_id = v_software_department_id
    and s.name = 'Software Engineering Fundamentals'
  on conflict (subject_id) do nothing;
end;
$$;

commit;
