-- =====================================================================
-- 0006: الإشعارات والإعلانات، الشكاوى، الملفات، سجل الإجراءات، الاستيراد، التقارير
-- كل إشعار له مفتاح فريد: لا تكرار مهما أعيد التشغيل
-- =====================================================================

create table public.notification_templates (
  id         uuid primary key default gen_random_uuid(),
  program_id uuid references public.programs(id) on delete cascade,   -- null = عام
  event_kind text not null,                      -- stage_completed, warning_issued, leave_decided ...
  channel    text not null check (channel in ('push', 'email', 'inbox')),
  title      text not null,
  body       text not null,                      -- متغيرات بصيغة {{student_name}}
  active     boolean not null default true,
  unique nulls not distinct (program_id, event_kind, channel)
);

-- الحدث: يقع مرة واحدة (dedupe_key فريد)
create table public.notification_events (
  id          uuid primary key default gen_random_uuid(),
  dedupe_key  text not null unique,              -- مثل: stage_completed:<enrollment>:<stage>
  event_kind  text not null,
  program_id  uuid references public.programs(id),
  enrollment_id uuid references public.enrollments(id) on delete cascade,
  payload     jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid references public.notification_events(id) on delete cascade,
  recipient_id uuid not null references public.app_users(id) on delete cascade,
  channel      text not null check (channel in ('push', 'email', 'inbox')),
  title        text not null,
  body         text not null,
  link         text,
  status       text not null default 'queued' check (status in ('queued', 'sent', 'failed', 'skipped')),
  attempts     int not null default 0,
  last_error   text,
  sent_at      timestamptz,
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);
create unique index notifications_once
  on public.notifications (event_id, recipient_id, channel) where event_id is not null;
create index notifications_inbox on public.notifications (recipient_id, created_at desc) where channel = 'inbox';
create index notifications_queue on public.notifications (status, created_at) where status = 'queued';

create table public.announcements (
  id          uuid primary key default gen_random_uuid(),
  program_id  uuid references public.programs(id) on delete cascade,
  audience    jsonb not null default '{}',       -- تصفية: دفعة، جنس، حالة ...
  title       text not null,
  body        text not null,
  publish_at  timestamptz not null default now(),
  expires_at  timestamptz,
  created_by  uuid references public.app_users(id),
  created_at  timestamptz not null default now()
);

-- اشتراكات الإشعارات الفورية لكل جهاز
create table public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.app_users(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  user_agent  text,
  platform    text,
  created_at  timestamptz not null default now(),
  last_used_at timestamptz,
  failed_count int not null default 0
);
create index push_subscriptions_user on public.push_subscriptions (user_id);

-- ---------------------------------------------------------------------
-- الشكاوى والملاحظات
-- ---------------------------------------------------------------------
create table public.complaints (
  id          uuid primary key default gen_random_uuid(),
  submitter_id uuid references public.app_users(id),
  program_id  uuid references public.programs(id),
  category    text not null,
  subject     text not null,
  body        text not null,
  anonymous   boolean not null default false,
  status      text not null default 'new' check (status in ('new', 'in_progress', 'resolved', 'closed')),
  assignee_id uuid references public.app_users(id),
  created_at  timestamptz not null default now()
);

create table public.complaint_actions (
  id           uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.complaints(id) on delete cascade,
  actor_id     uuid references public.app_users(id),
  action       text not null,
  note         text,
  visible_to_submitter boolean not null default false,
  created_at   timestamptz not null default now()
);

-- الملفات (المحتوى نفسه في Supabase Storage)
create table public.files (
  id           uuid primary key default gen_random_uuid(),
  bucket       text not null,
  path         text not null,
  owner_id     uuid references public.app_users(id),
  mime_type    text,
  size_bytes   bigint,
  created_at   timestamptz not null default now(),
  unique (bucket, path)
);

-- ---------------------------------------------------------------------
-- سجل الإجراءات: إضافة فقط
-- ---------------------------------------------------------------------
create table public.audit_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid references public.app_users(id),
  action      text not null,
  entity      text not null,
  entity_id   text,
  before      jsonb,
  after       jsonb,
  reason      text,
  ip          inet,
  at          timestamptz not null default now()
);
create index audit_log_entity on public.audit_log (entity, entity_id);
create index audit_log_at on public.audit_log (at desc);

create or replace function public.forbid_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'هذا الجدول للإضافة فقط';
end $$;
create trigger audit_log_append_only before update or delete on public.audit_log
  for each row execute function public.forbid_mutation();

-- ---------------------------------------------------------------------
-- الاستيراد من النظام القديم: كل صف مرة واحدة
-- ---------------------------------------------------------------------
create table public.import_batches (
  id          uuid primary key default gen_random_uuid(),
  source      text not null,                     -- google_sheets, cloudflare_kv, csv
  file_ref    text not null,
  started_by  uuid references public.app_users(id),
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  stats       jsonb not null default '{}',
  status      text not null default 'running' check (status in ('running', 'done', 'failed', 'rolled_back'))
);

create table public.import_rows (
  id          uuid primary key default gen_random_uuid(),
  batch_id    uuid not null references public.import_batches(id) on delete cascade,
  file_ref    text not null,
  sheet       text not null,
  row_no      int not null,
  raw         jsonb not null,
  row_hash    text not null,
  status      text not null check (status in ('imported', 'skipped', 'error', 'needs_review')),
  message     text,
  target_entity text,
  target_id   uuid,
  created_at  timestamptz not null default now(),
  unique (file_ref, sheet, row_no)
);

alter table public.daily_records
  add constraint daily_records_import_row_fk foreign key (import_row_id) references public.import_rows(id);

-- لقطات التقارير (الأسبوعي، لوحة الشرف) لتثبيت ما أُرسل
create table public.report_snapshots (
  id          uuid primary key default gen_random_uuid(),
  program_id  uuid references public.programs(id) on delete cascade,
  kind        text not null,                     -- weekly_report, honor_board, admin_summary
  period_from date,
  period_to   date,
  params      jsonb not null default '{}',
  data        jsonb not null,
  created_at  timestamptz not null default now()
);
create index report_snapshots_lookup on public.report_snapshots (program_id, kind, period_to desc);
