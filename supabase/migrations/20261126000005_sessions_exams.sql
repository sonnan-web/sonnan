-- =====================================================================
-- 0005: الفترات والحجوزات، الاختبارات وبنك الأسئلة، تقدّم المراحل
-- =====================================================================

-- الفترة: موعد أسبوعي ثابت عند معلم بسعة محددة
create table public.slots (
  id          uuid primary key default gen_random_uuid(),
  teacher_id  uuid not null references public.app_users(id),
  weekday     int not null check (weekday between 0 and 6),   -- 0 = الأحد
  start_time  time not null,                     -- بتوقيت مكة
  duration_min int not null check (duration_min > 0),
  capacity    int not null check (capacity > 0),
  gender      text check (gender in ('male', 'female')),
  meeting_url text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table public.slot_programs (
  slot_id    uuid not null references public.slots(id) on delete cascade,
  program_id uuid not null references public.programs(id) on delete cascade,
  primary key (slot_id, program_id)
);

create table public.slot_bookings (
  id            uuid primary key default gen_random_uuid(),
  slot_id       uuid not null references public.slots(id),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  status        text not null default 'active' check (status in ('active', 'cancelled', 'moved')),
  booked_at     timestamptz not null default now(),
  ended_at      timestamptz,
  ended_reason  text
);
create unique index slot_bookings_one_active
  on public.slot_bookings (enrollment_id) where status = 'active';
create index slot_bookings_slot on public.slot_bookings (slot_id) where status = 'active';

-- منع تجاوز السعة حتى مع الحجز المتزامن
create or replace function public.enforce_slot_capacity()
returns trigger language plpgsql as $$
declare
  cap int;
  used int;
begin
  if new.status <> 'active' then
    return new;
  end if;
  select capacity into cap from public.slots where id = new.slot_id and active for update;
  if cap is null then
    raise exception 'الفترة غير متاحة';
  end if;
  select count(*) into used from public.slot_bookings
    where slot_id = new.slot_id and status = 'active' and id <> new.id;
  if used >= cap then
    raise exception 'اكتملت سعة هذه الفترة';
  end if;
  return new;
end $$;
create trigger slot_bookings_capacity before insert or update of status, slot_id on public.slot_bookings
  for each row execute function public.enforce_slot_capacity();

create table public.booking_change_requests (
  id            uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  from_booking_id uuid references public.slot_bookings(id),
  to_slot_id    uuid references public.slots(id),
  reason        text not null,
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by    uuid references public.app_users(id),
  decided_at    timestamptz,
  created_at    timestamptz not null default now()
);

-- لقاء فعلي في تاريخ محدد (يُولَّد من الفترة)، يمكن إلغاؤه أو نقله
create table public.session_occurrences (
  id         uuid primary key default gen_random_uuid(),
  slot_id    uuid not null references public.slots(id) on delete cascade,
  starts_at  timestamptz not null,
  status     text not null default 'scheduled' check (status in ('scheduled', 'held', 'cancelled', 'moved')),
  note       text,
  unique (slot_id, starts_at)
);

-- ---------------------------------------------------------------------
-- الاختبارات
-- ---------------------------------------------------------------------
create table public.questions (
  id         uuid primary key default gen_random_uuid(),
  program_id uuid references public.programs(id),
  book_id    uuid references public.books(id),
  volume_no  int,
  from_unit  numeric(10,2),
  to_unit    numeric(10,2),
  kind       text not null check (kind in ('oral_recite', 'mcq', 'short_answer', 'complete_text')),
  prompt     text not null,
  payload    jsonb not null default '{}',        -- الخيارات والإجابة النموذجية
  difficulty int check (difficulty between 1 and 5),
  active     boolean not null default true,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now()
);
create index questions_scope on public.questions (book_id, volume_no, from_unit);

create table public.exam_templates (
  id          uuid primary key default gen_random_uuid(),
  program_id  uuid not null references public.programs(id) on delete cascade,
  name        text not null,
  scope       text not null check (scope in ('stage', 'volume', 'book', 'custom')),
  mode        text not null check (mode in ('oral', 'online', 'mixed')),
  rules       jsonb not null,                    -- عدد الأسئلة، المدة، درجة النجاح، المحاولات
  active      boolean not null default true
);

create table public.exam_forms (
  id          uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.exam_templates(id) on delete cascade,
  label       text not null,
  generated_at timestamptz not null default now()
);

create table public.exam_form_questions (
  form_id     uuid not null references public.exam_forms(id) on delete cascade,
  question_id uuid not null references public.questions(id),
  seq         int not null,
  points      numeric(6,2) not null,
  primary key (form_id, question_id),
  unique (form_id, seq)
);

create table public.exam_appointments (
  id            uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  template_id   uuid not null references public.exam_templates(id),
  stage_id      uuid references public.stages(id),
  examiner_id   uuid references public.app_users(id),
  scheduled_at  timestamptz,
  status        text not null default 'requested'
                check (status in ('requested', 'scheduled', 'done', 'missed', 'cancelled')),
  created_at    timestamptz not null default now()
);

create table public.exam_attempts (
  id             uuid primary key default gen_random_uuid(),
  appointment_id uuid references public.exam_appointments(id),
  enrollment_id  uuid not null references public.enrollments(id) on delete cascade,
  form_id        uuid references public.exam_forms(id),
  attempt_no     int not null default 1,
  started_at     timestamptz,
  submitted_at   timestamptz,
  score          numeric(6,2),
  max_score      numeric(6,2),
  passed         boolean,
  graded_by      uuid references public.app_users(id),
  status         text not null default 'in_progress'
                 check (status in ('in_progress', 'submitted', 'graded', 'void')),
  void_reason    text
);

create table public.attempt_answers (
  attempt_id  uuid not null references public.exam_attempts(id) on delete cascade,
  question_id uuid not null references public.questions(id),
  answer      jsonb,
  points      numeric(6,2),
  feedback    text,
  primary key (attempt_id, question_id)
);

-- أحداث المحاولة: خروج من الصفحة، انقطاع، إعادة دخول
create table public.attempt_events (
  id         bigint generated always as identity primary key,
  attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  kind       text not null,
  detail     jsonb,
  at         timestamptz not null default now()
);

-- تقدّم المراحل
create table public.stage_progress (
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  stage_id      uuid not null references public.stages(id),
  status        text not null default 'in_progress'
                check (status in ('not_started', 'in_progress', 'reached_end', 'completed', 'exam_failed')),
  reached_end_at timestamptz,
  completed_at  timestamptz,
  gaps          jsonb not null default '[]',      -- نطاقات لم تُسمَّع (تُنبّه المشرف)
  updated_at    timestamptz not null default now(),
  primary key (enrollment_id, stage_id)
);
