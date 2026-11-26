-- =====================================================================
-- خطة البرنامج: أعمدة وقواعد يحددها المشرف (إضافة على قاعدة منصة رواد سنن)
-- لا يمس الجداول الحالية. طُبّق واختُبر على المشروع التجريبي sonnan-staging.
-- =====================================================================
create table public.program_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  book_name text,
  audio_url text, book_url text, whatsapp_url text,
  status text not null default 'draft' check (status in ('draft','active','archived')),
  workdays smallint[] not null default '{0,1,2,3,4}',
  recitation_mode text not null default 'daily' check (recitation_mode in ('daily','days','none')),
  recitation_days smallint[] not null default '{}',
  student_execution text not null default 'counts' check (student_execution in ('none','record_only','counts')),
  execution_weight numeric(5,2),
  recitation_weight numeric(5,2),
  score_rules jsonb not null default '{"max":10,"deductions":[{"key":"full","label":"خطأ كامل","value":1},{"key":"half","label":"نصف خطأ","value":0.5},{"key":"quarter","label":"ربع خطأ","value":0.25}]}',
  discipline_rules jsonb not null default '{}',
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.plan_columns (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.program_plans(id) on delete cascade,
  seq int not null,
  header text not null,
  task text not null check (task in ('memo','link','review','repeat','explain','listen','custom')),
  task_label text,
  value_type text not null default 'number' check (value_type in ('number','text','url','bool')),
  range_role text not null default 'single' check (range_role in ('single','start','end')),
  pair_column_id uuid references public.plan_columns(id) on delete set null,
  executor text not null default 'both' check (executor in ('student','teacher','both','info')),
  counts boolean not null default true,
  weight numeric(5,2),
  required boolean not null default false,
  constraint plan_columns_plan_id_header_key unique (plan_id, header) deferrable initially deferred,
  constraint plan_columns_plan_id_seq_key unique (plan_id, seq) deferrable initially deferred
);

create table public.plan_days (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.program_plans(id) on delete cascade,
  day_number int not null check (day_number > 0),
  vals jsonb not null default '{}',
  unique (plan_id, day_number)
);

create table public.plan_assignments (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.program_plans(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  start_date date not null default (now() at time zone 'Asia/Riyadh')::date,
  start_day int not null default 1 check (start_day > 0),
  assigned_by uuid references public.users(id),
  assigned_at timestamptz not null default now(),
  ended_at timestamptz
);
create unique index plan_assignments_one_active on public.plan_assignments (student_id) where ended_at is null;

create table public.plan_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  plan_day_id uuid not null references public.plan_days(id) on delete cascade,
  column_id uuid not null references public.plan_columns(id) on delete cascade,
  done boolean not null default true,
  done_at timestamptz not null default now(),
  unique (student_id, plan_day_id, column_id)
);

create table public.plan_recitations (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  teacher_id uuid references public.teachers(id),
  plan_day_id uuid references public.plan_days(id) on delete set null,
  rec_date date not null default (now() at time zone 'Asia/Riyadh')::date,
  vals jsonb not null default '{}',
  deductions jsonb not null default '{}',
  score numeric(5,2),
  notes text,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  superseded_by uuid references public.plan_recitations(id),
  edit_reason text
);
create unique index plan_recitations_current on public.plan_recitations (student_id, rec_date) where superseded_by is null;

create or replace function public.plan_touch() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;
create trigger program_plans_touch before update on public.program_plans for each row execute function public.plan_touch();

create or replace function public.current_plan_of(stu uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select plan_id from public.plan_assignments where student_id = stu and ended_at is null
$$;
revoke execute on function public.current_plan_of(uuid) from anon, public;
grant execute on function public.current_plan_of(uuid) to authenticated;

alter table public.program_plans enable row level security;
alter table public.plan_columns enable row level security;
alter table public.plan_days enable row level security;
alter table public.plan_assignments enable row level security;
alter table public.plan_progress enable row level security;
alter table public.plan_recitations enable row level security;

create policy admin_all on public.program_plans for all to authenticated using (public.get_current_user_role() = 'admin') with check (public.get_current_user_role() = 'admin');
create policy admin_all on public.plan_columns for all to authenticated using (public.get_current_user_role() = 'admin') with check (public.get_current_user_role() = 'admin');
create policy admin_all on public.plan_days for all to authenticated using (public.get_current_user_role() = 'admin') with check (public.get_current_user_role() = 'admin');
create policy admin_all on public.plan_assignments for all to authenticated using (public.get_current_user_role() = 'admin') with check (public.get_current_user_role() = 'admin');
create policy admin_all on public.plan_progress for all to authenticated using (public.get_current_user_role() = 'admin') with check (public.get_current_user_role() = 'admin');
create policy admin_all on public.plan_recitations for all to authenticated using (public.get_current_user_role() = 'admin') with check (public.get_current_user_role() = 'admin');

create policy read_plans on public.program_plans for select to authenticated using (public.get_current_user_role() in ('teacher','student'));
create policy read_columns on public.plan_columns for select to authenticated using (public.get_current_user_role() in ('teacher','student'));
create policy read_days on public.plan_days for select to authenticated using (public.get_current_user_role() in ('teacher','student'));

create policy teacher_assignments on public.plan_assignments for select to authenticated using (
  exists (select 1 from public.students s where s.id = student_id and s.teacher_id = public.get_teacher_id_for_current_user()));
create policy student_assignment on public.plan_assignments for select to authenticated using (student_id = public.get_student_id_for_current_user());

create policy student_progress_read on public.plan_progress for select to authenticated using (student_id = public.get_student_id_for_current_user());
create policy student_progress_write on public.plan_progress for insert to authenticated with check (
  student_id = public.get_student_id_for_current_user()
  and exists (select 1 from public.plan_columns c join public.program_plans p on p.id = c.plan_id
              where c.id = column_id and c.executor in ('student','both') and p.student_execution <> 'none'
                and p.id = public.current_plan_of(student_id)));
create policy student_progress_delete on public.plan_progress for delete to authenticated using (student_id = public.get_student_id_for_current_user());
create policy teacher_progress_read on public.plan_progress for select to authenticated using (
  exists (select 1 from public.students s where s.id = student_id and s.teacher_id = public.get_teacher_id_for_current_user()));

create policy teacher_rec_read on public.plan_recitations for select to authenticated using (
  exists (select 1 from public.students s where s.id = student_id and s.teacher_id = public.get_teacher_id_for_current_user()));
create policy teacher_rec_insert on public.plan_recitations for insert to authenticated with check (
  teacher_id = public.get_teacher_id_for_current_user()
  and exists (select 1 from public.students s where s.id = student_id and s.teacher_id = teacher_id));
create policy student_rec_read on public.plan_recitations for select to authenticated using (student_id = public.get_student_id_for_current_user());
