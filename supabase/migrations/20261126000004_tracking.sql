-- =====================================================================
-- 0004: الرصد اليومي، الاستئذان، الانضباط، المتابعة، حالة اليوم المحسوبة
-- السجل لا يُحذف: يُستبدَل (superseded) ويبقى أثره
-- =====================================================================

create table public.daily_records (
  id             uuid primary key default gen_random_uuid(),
  enrollment_id  uuid not null references public.enrollments(id) on delete cascade,
  credited_date  date not null,                  -- اليوم الذي يُحسب له الإنجاز
  actual_date    date not null,                  -- اليوم الذي تم فيه فعلًا
  status_key     text not null,                  -- من قائمة البرنامج: present, absent, excused, makeup, review_only ...
  makes_up_date  date,                           -- للتعويض: اليوم الفائت المرتبط
  recorder_role  text not null check (recorder_role in ('teacher', 'student', 'admin', 'import', 'system')),
  recorded_by    uuid references public.app_users(id),
  note           text,
  superseded_by  uuid references public.daily_records(id),
  supersede_reason text,
  source         text not null default 'app' check (source in ('app', 'import', 'api')),
  import_row_id  uuid,
  created_at     timestamptz not null default now(),
  -- التعويض يُحسب في يوم أدائه، ويرتبط باليوم الفائت السابق له
  constraint daily_records_makeup check (makes_up_date is null or makes_up_date < credited_date)
);
create unique index daily_records_current
  on public.daily_records (enrollment_id, credited_date, recorder_role)
  where superseded_by is null;
create index daily_records_by_date on public.daily_records (credited_date);
create index daily_records_makeup on public.daily_records (enrollment_id, makes_up_date) where makes_up_date is not null;

-- لا حذف ولا تعديل للمحتوى؛ المسموح فقط وضع superseded_by مرة واحدة
create or replace function public.guard_daily_records()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'سجلات الرصد لا تُحذف؛ استبدلها بسجل جديد';
  end if;
  if old.superseded_by is not null then
    raise exception 'هذا السجل مستبدَل مسبقًا';
  end if;
  if (to_jsonb(new) - 'superseded_by' - 'supersede_reason') <> (to_jsonb(old) - 'superseded_by' - 'supersede_reason') then
    raise exception 'لا يُعدَّل محتوى سجل الرصد؛ أنشئ سجلًا جديدًا يستبدله';
  end if;
  return new;
end $$;
create trigger daily_records_guard before update or delete on public.daily_records
  for each row execute function public.guard_daily_records();

-- بنود السجل: ما سُمِّع فعلًا (يقبل الكسور: نصف حديث، نصف صفحة)
create table public.record_items (
  id         uuid primary key default gen_random_uuid(),
  record_id  uuid not null references public.daily_records(id) on delete cascade,
  kind       text not null check (kind in ('memorize', 'review', 'link', 'test')),
  book_id    uuid references public.books(id),
  volume_no  int,
  from_unit  numeric(10,2),
  to_unit    numeric(10,2),
  amount     numeric(10,2),                      -- عند عدم وجود نطاق (مثل عدد صفحات المراجعة)
  constraint record_items_range check (from_unit is null or to_unit is null or to_unit >= from_unit),
  constraint record_items_has_quantity check (amount is not null or (from_unit is not null and to_unit is not null))
);
create index record_items_record on public.record_items (record_id);

-- التقييم: درجة الضبط ودرجة الالتزام وغيرهما بحسب إعداد البرنامج
create table public.record_assessments (
  record_id uuid not null references public.daily_records(id) on delete cascade,
  metric    text not null,                       -- control, commitment, ...
  score     numeric(6,2) not null,
  max_score numeric(6,2) not null,
  primary key (record_id, metric),
  constraint record_assessments_bounds check (score between 0 and max_score)
);

-- ---------------------------------------------------------------------
-- الاستئذان
-- ---------------------------------------------------------------------
create table public.leave_requests (
  id            uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  date_from     date not null,
  date_to       date not null,
  reason_key    text not null,
  details       text,
  attachment_id uuid,
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by    uuid references public.app_users(id),
  decided_at    timestamptz,
  decision_note text,
  created_at    timestamptz not null default now(),
  constraint leave_period check (date_to >= date_from)
);
create index leave_requests_enrollment on public.leave_requests (enrollment_id, status);

-- ---------------------------------------------------------------------
-- الانضباط: التنبيهات والإنذارات (مفتاح فريد يمنع التكرار)
-- ---------------------------------------------------------------------
create table public.discipline_events (
  id             uuid primary key default gen_random_uuid(),
  enrollment_id  uuid not null references public.enrollments(id) on delete cascade,
  kind           text not null,                  -- alert, warning, escalation, dismissal_notice ...
  level          int not null default 1,
  trigger_date   date not null,
  rule_snapshot  jsonb not null,                 -- قيمة الإعداد وقت الاحتساب
  evidence       jsonb not null default '{}',    -- الأيام التي أدّت للحدث
  status         text not null default 'active' check (status in ('active', 'revoked')),
  revoked_reason text,
  created_by     uuid references public.app_users(id),
  created_at     timestamptz not null default now(),
  unique (enrollment_id, kind, trigger_date)
);

create table public.follow_up_cases (
  id            uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  opened_by_event uuid references public.discipline_events(id),
  assignee_id   uuid references public.app_users(id),
  status        text not null default 'open' check (status in ('open', 'in_progress', 'resolved', 'closed')),
  outcome       text,
  opened_at     timestamptz not null default now(),
  closed_at     timestamptz
);
create index follow_up_cases_open on public.follow_up_cases (status, assignee_id);

create table public.case_contacts (
  id         uuid primary key default gen_random_uuid(),
  case_id    uuid not null references public.follow_up_cases(id) on delete cascade,
  channel    text not null check (channel in ('call', 'whatsapp', 'email', 'meeting', 'other')),
  summary    text not null,
  contacted_by uuid references public.app_users(id),
  contacted_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- حالة اليوم المحسوبة: يكتبها محرّك الحساب فقط، ويمكن إعادة توليدها
-- ---------------------------------------------------------------------
create table public.enrollment_day_status (
  enrollment_id   uuid not null references public.enrollments(id) on delete cascade,
  day             date not null,
  is_workday      boolean not null,
  workday_index   int,
  expected        jsonb,                         -- المطلوب من الخطة
  effective_status text not null,                -- الحالة بعد دمج الرصد والاستئذان والتعويض
  achieved_units  numeric(10,2) not null default 0,
  counts_as_achievement boolean not null default false,
  weight          numeric(4,2),
  settings_version_id uuid references public.program_settings_versions(id),
  engine_version  text not null,
  computed_at     timestamptz not null default now(),
  primary key (enrollment_id, day)
);
create index eds_day on public.enrollment_day_status (day);
