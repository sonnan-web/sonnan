-- =====================================================================
-- 0003: التقديم والقبول، التسجيلات، الإسناد، الاستثناءات والتقويم
-- الطالب ≠ التسجيل: الطالب الواحد قد يسجّل في أكثر من برنامج أو دورة
-- =====================================================================

create table public.application_forms (
  id         uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.programs(id) on delete cascade,
  title      text not null,
  schema     jsonb not null,                     -- الحقول وشروطها، تُبنى من لوحة المشرف
  opens_at   timestamptz,
  closes_at  timestamptz,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.applications (
  id            uuid primary key default gen_random_uuid(),
  form_id       uuid not null references public.application_forms(id),
  program_id    uuid not null references public.programs(id),
  email         citext not null,
  user_id       uuid references public.app_users(id),
  answers       jsonb not null,
  status        text not null default 'submitted'
                check (status in ('submitted', 'under_review', 'accepted', 'rejected', 'waitlisted', 'withdrawn')),
  decision_note text,
  decided_by    uuid references public.app_users(id),
  decided_at    timestamptz,
  submitted_at  timestamptz not null default now()
);
create index applications_program_status on public.applications (program_id, status);
create index applications_email on public.applications (email);

create table public.enrollments (
  id               uuid primary key default gen_random_uuid(),
  student_id       uuid not null references public.app_users(id),
  program_id       uuid not null references public.programs(id),
  application_id   uuid references public.applications(id),
  cohort           text,                         -- الدفعة
  start_date       date not null,
  end_date         date,
  status           text not null default 'active'
                   check (status in ('pending', 'active', 'paused', 'withdrawn', 'dismissed', 'completed', 'transferred')),
  legacy_ref       text,                         -- المعرّف في النظام القديم
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint enrollments_period check (end_date is null or end_date >= start_date)
);
create unique index enrollments_one_open_per_program
  on public.enrollments (student_id, program_id)
  where status in ('pending', 'active', 'paused');
create index enrollments_program on public.enrollments (program_id, status);
create trigger enrollments_touch before update on public.enrollments
  for each row execute function public.touch_updated_at();

create table public.enrollment_status_history (
  id            bigint generated always as identity primary key,
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  from_status   text,
  to_status     text not null,
  reason        text,
  changed_by    uuid references public.app_users(id),
  changed_at    timestamptz not null default now()
);

create or replace function public.log_enrollment_status()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.enrollment_status_history (enrollment_id, from_status, to_status)
    values (new.id, case when tg_op = 'UPDATE' then old.status end, new.status);
  end if;
  return new;
end $$;
create trigger enrollments_status_log after insert or update of status on public.enrollments
  for each row execute function public.log_enrollment_status();

-- أي خطة يتبعها الطالب ومن أي يوم عمل يبدأ
create table public.enrollment_plans (
  id                uuid primary key default gen_random_uuid(),
  enrollment_id     uuid not null references public.enrollments(id) on delete cascade,
  plan_version_id   uuid not null references public.plan_versions(id),
  start_date        date not null,
  start_workday     int not null default 1 check (start_workday > 0),
  end_date          date,
  reason            text,
  created_by        uuid references public.app_users(id),
  created_at        timestamptz not null default now(),
  constraint enrollment_plans_no_overlap exclude using gist (
    enrollment_id with =, daterange(start_date, end_date, '[)') with &&
  )
);

create table public.teacher_assignments (
  id            uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  teacher_id    uuid not null references public.app_users(id),
  valid_from    date not null,
  valid_to      date,
  created_by    uuid references public.app_users(id),
  created_at    timestamptz not null default now(),
  constraint teacher_assignments_no_overlap exclude using gist (
    enrollment_id with =, daterange(valid_from, valid_to, '[)') with &&
  )
);
create index teacher_assignments_teacher on public.teacher_assignments (teacher_id);

-- استثناء إعداد لطالب بعينه (مثلًا: أيام عمل مختلفة) مع سبب
create table public.enrollment_setting_overrides (
  id             uuid primary key default gen_random_uuid(),
  enrollment_id  uuid not null references public.enrollments(id) on delete cascade,
  setting_path   text not null,                  -- مثل: attendance.workdays
  value          jsonb not null,
  effective_from date not null,
  effective_to   date,
  reason         text not null,
  created_by     uuid references public.app_users(id),
  created_at     timestamptz not null default now()
);
create index eso_enrollment on public.enrollment_setting_overrides (enrollment_id, setting_path);

-- التقويم: إجازات وتعطيلات على مستوى الجمعية أو البرنامج
create table public.calendar_exceptions (
  id         uuid primary key default gen_random_uuid(),
  program_id uuid references public.programs(id) on delete cascade,  -- null = كل البرامج
  date_from  date not null,
  date_to    date not null,
  kind       text not null check (kind in ('holiday', 'suspension', 'extra_workday')),
  label      text not null,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  constraint calendar_exceptions_period check (date_to >= date_from)
);
create index calendar_exceptions_lookup on public.calendar_exceptions (program_id, date_from, date_to);
