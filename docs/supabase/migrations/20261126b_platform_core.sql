-- =====================================================================
-- منصة سنن: إضافات الطلاب والفترات والرصد والاستئذان والانضباط والاختبارات والإشعارات
-- تُطبَّق بعد 20261126_program_plans.sql. طُبّقت واختُبرت على المشروع التجريبي sonnan-staging.
-- ملاحظة مهمة قبل التطبيق على مشروع المنصة: هذا الملف يحذف عمود users.password (كلمات المرور مكانها نظام الدخول فقط).
-- =====================================================================

alter table public.students
  add column if not exists gender text, add column if not exists nationality text, add column if not exists residence text,
  add column if not exists birth_date date, add column if not exists phone text, add column if not exists education text,
  add column if not exists quran_parts numeric(4,1), add column if not exists app_status text, add column if not exists notes text,
  add column if not exists volume text, add column if not exists legacy_ref text;
alter table public.users add column if not exists is_active boolean not null default true;
alter table public.users drop column if exists password;

create table if not exists public.user_profiles (
  id uuid primary key references public.users(id) on delete cascade,
  avatar_url text, birth_date date, gender text, nationality text, city text, workplace text,
  qualifications text, quran_memorization text, skills text, bio text, updated_at timestamptz not null default now());

create table if not exists public.audio_rooms (
  id uuid primary key default gen_random_uuid(), name text not null, meet_url text, days text[] not null default '{}',
  start_time time, end_time time,
  outside_behavior text not null default 'disabled' check (outside_behavior in ('disabled','hidden','always_visible')),
  capacity int, sort int not null default 0, active boolean not null default true, created_at timestamptz not null default now());
create table if not exists public.room_assignments (
  id uuid primary key default gen_random_uuid(), room_id uuid not null references public.audio_rooms(id) on delete cascade,
  assignee_type text not null check (assignee_type in ('teacher','student')), assignee_id uuid not null,
  created_at timestamptz not null default now(), unique (room_id, assignee_type, assignee_id));

drop index if exists public.plan_recitations_current;
alter table public.plan_recitations
  add column if not exists status text not null default 'present' check (status in ('present','makeup','review_only','excused','absent')),
  add column if not exists makes_up_date date,
  add column if not exists room_id uuid references public.audio_rooms(id) on delete set null,
  add column if not exists plan_id uuid references public.program_plans(id) on delete set null,
  add column if not exists legacy jsonb,
  add column if not exists memo_from numeric(10,2), add column if not exists memo_to numeric(10,2), add column if not exists errors_total numeric(6,2);
create index if not exists plan_recitations_student_date on public.plan_recitations (student_id, rec_date desc);
create index if not exists plan_recitations_date on public.plan_recitations (rec_date);

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id) on delete cascade,
  date_from date not null, date_to date not null, reason text not null, details text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  decided_by uuid references public.users(id), decided_at timestamptz, decision_note text,
  created_at timestamptz not null default now(), check (date_to >= date_from));
create table if not exists public.discipline_events (
  id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id) on delete cascade,
  kind text not null check (kind in ('alert','warning','dismissal')), event_date date not null, reason text,
  details jsonb not null default '{}', status text not null default 'active' check (status in ('active','revoked')),
  created_by uuid references public.users(id), created_at timestamptz not null default now(), unique (student_id, kind, event_date));
create table if not exists public.follow_up_actions (
  id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id) on delete cascade,
  case_date date not null, reason text, contact_date date, contact_method text, action_summary text, student_reply text,
  status text not null default 'open', created_by uuid references public.users(id), created_at timestamptz not null default now());
create table if not exists public.periodic_exams (
  id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id) on delete cascade,
  exam_name text not null, stage int, volume text, score numeric(5,2),
  date date not null default (now() at time zone 'Asia/Riyadh')::date, notes text,
  created_by uuid references public.users(id), created_at timestamptz not null default now());
alter table public.periodic_exams add column if not exists stage int, add column if not exists volume text,
  add column if not exists created_by uuid references public.users(id), add column if not exists created_at timestamptz not null default now();

-- الإشعارات: صندوق داخل المنصة + بريد + جوال. البريد والجوال يبقيان «queued» حتى تُرسلهما دالة خادم.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(), recipient_user_id uuid not null references public.users(id) on delete cascade,
  channel text not null default 'inbox' check (channel in ('inbox','email','push')), kind text not null default 'manual',
  title text not null, body text not null, link text, dedupe_key text unique,
  status text not null default 'queued' check (status in ('queued','sent','failed','skipped')), error text,
  created_by uuid references public.users(id), created_at timestamptz not null default now(), sent_at timestamptz, read_at timestamptz);
create index if not exists notifications_inbox on public.notifications (recipient_user_id, created_at desc);
create index if not exists notifications_queue on public.notifications (status, channel) where status = 'queued';
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.users(id) on delete cascade,
  endpoint text not null unique, p256dh text not null, auth text not null, user_agent text, created_at timestamptz not null default now());

-- ===== دوال =====
create or replace function public.is_my_student(stu uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.students s where s.id = stu and s.teacher_id = public.get_teacher_id_for_current_user()) $$;
create or replace function public.my_teacher_user_id() returns uuid language sql stable security definer set search_path = '' as $$
  select t.user_id from public.students s join public.teachers t on t.id = s.teacher_id where s.user_id = auth.uid() limit 1 $$;

create or replace function public.memorized_of(p_student uuid) returns numeric language sql stable security definer set search_path = '' as $$
  select case when public.get_current_user_role() = 'admin' or p_student = public.get_student_id_for_current_user() or public.is_my_student(p_student)
  then (select coalesce(sum(upper(x) - lower(x)), 0) from (
    select unnest(range_agg(numrange(least(memo_from, memo_to) - 0.5, greatest(memo_from, memo_to) + 0.5, '[)'))) x
    from public.plan_recitations where student_id = p_student and superseded_by is null and status in ('present','makeup')
      and memo_from is not null and memo_to is not null and memo_from > 0) q) end $$;

create or replace function public.honor_board(p_plan uuid default null, p_from date default null, p_to date default null)
returns table (student_id uuid, name text, memorized numeric, sessions int, avg_score numeric)
language sql stable security definer set search_path = '' as $$
  with r as (select pr.student_id, pr.score, pr.memo_from f, pr.memo_to t from public.plan_recitations pr
    where pr.superseded_by is null and pr.status in ('present','makeup') and (p_plan is null or pr.plan_id = p_plan)
      and (p_from is null or pr.rec_date >= p_from) and (p_to is null or pr.rec_date <= p_to)),
  merged as (select student_id, sum(upper(x) - lower(x)) m from (
      select student_id, unnest(range_agg(numrange(least(f,t) - 0.5, greatest(f,t) + 0.5, '[)'))) x from r where f is not null and t is not null and f > 0 group by student_id) q group by student_id)
  select s.id, u.name, coalesce(m.m, 0), (select count(*)::int from r where r.student_id = s.id), (select round(avg(score),2) from r where r.student_id = s.id)
  from public.students s join public.users u on u.id = s.user_id left join merged m on m.student_id = s.id
  where s.is_archived = false and s.status = 'active' order by 3 desc, 5 desc nulls last $$;

-- إنشاء الحسابات وتعيين كلمة المرور من لوحة المشرف (بديل دالة manage-student)
create or replace function public.admin_create_account(p_email text, p_name text, p_role text, p_password text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid; em text := lower(btrim(p_email));
begin
  if public.get_current_user_role() is distinct from 'admin' then raise exception 'للمشرف فقط'; end if;
  if p_role not in ('admin','teacher','student') then raise exception 'دور غير صالح'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'بريد غير صالح: %', p_email; end if;
  if length(coalesce(p_password,'')) < 8 then raise exception 'كلمة المرور يجب ألا تقل عن 8 أحرف'; end if;
  select id into uid from public.users where lower(email) = em; if uid is not null then return uid; end if;
  select id into uid from auth.users where lower(email) = em;
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em, extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', jsonb_build_object('name', p_name), now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true), 'email', now(), now(), now());
  end if;
  insert into public.users (id, name, email, role) values (uid, p_name, em, p_role);
  return uid;
end $$;
create or replace function public.admin_set_password(p_user uuid, p_password text) returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.get_current_user_role() is distinct from 'admin' then raise exception 'للمشرف فقط'; end if;
  if length(coalesce(p_password,'')) < 8 then raise exception 'كلمة المرور يجب ألا تقل عن 8 أحرف'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now() where id = p_user;
end $$;

do $$ declare f text; begin
  foreach f in array array['public.is_my_student(uuid)','public.my_teacher_user_id()','public.memorized_of(uuid)','public.honor_board(uuid,date,date)','public.admin_create_account(text,text,text,text)','public.admin_set_password(uuid,text)'] loop
    execute 'revoke execute on function ' || f || ' from anon, public';
    execute 'grant execute on function ' || f || ' to authenticated';
  end loop;
end $$;

-- ===== الصلاحيات =====
do $$ declare t text; begin
  foreach t in array array['user_profiles','audio_rooms','room_assignments','leave_requests','discipline_events','follow_up_actions','periodic_exams','notifications','push_subscriptions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists admin_all on public.%I', t);
    execute format('create policy admin_all on public.%I for all to authenticated using (public.get_current_user_role() = ''admin'') with check (public.get_current_user_role() = ''admin'')', t);
  end loop;
end $$;
create policy own_profile on public.user_profiles for all to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy read_rooms on public.audio_rooms for select to authenticated using (true);
create policy own_room_assign on public.room_assignments for select to authenticated using (
  (assignee_type = 'teacher' and assignee_id = public.get_teacher_id_for_current_user())
  or (assignee_type = 'student' and (assignee_id = public.get_student_id_for_current_user() or public.is_my_student(assignee_id))));
create policy student_leave_read on public.leave_requests for select to authenticated using (student_id = public.get_student_id_for_current_user() or public.is_my_student(student_id));
create policy student_leave_insert on public.leave_requests for insert to authenticated with check (student_id = public.get_student_id_for_current_user() and status = 'pending' and decided_by is null);
create policy discipline_read on public.discipline_events for select to authenticated using (student_id = public.get_student_id_for_current_user() or public.is_my_student(student_id));
create policy exams_read on public.periodic_exams for select to authenticated using (student_id = public.get_student_id_for_current_user() or public.is_my_student(student_id));
create policy own_notifications on public.notifications for select to authenticated using (recipient_user_id = auth.uid());
create policy own_notifications_read on public.notifications for update to authenticated using (recipient_user_id = auth.uid()) with check (recipient_user_id = auth.uid());
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy own_push on public.push_subscriptions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy teacher_rec_supersede on public.plan_recitations for update to authenticated using (public.is_my_student(student_id) and superseded_by is null) with check (public.is_my_student(student_id));
revoke update on public.plan_recitations from authenticated;
grant update (superseded_by, edit_reason) on public.plan_recitations to authenticated;
create policy student_sees_teacher on public.users for select to authenticated using (id = public.my_teacher_user_id());
create policy student_sees_teacher_row on public.teachers for select to authenticated using (user_id = public.my_teacher_user_id());

-- ===== إضافة لاحقة: بيانات الإثبات للمشرف فقط، والأرشفة، وتعديل اسم الحساب وبريده =====
create table if not exists public.student_private (
  student_id uuid primary key references public.students(id) on delete cascade,
  id_number text, id_type text, updated_at timestamptz not null default now());
alter table public.student_private enable row level security;
create policy admin_all on public.student_private for all to authenticated
  using (public.get_current_user_role() = 'admin') with check (public.get_current_user_role() = 'admin');
drop policy if exists teacher_own_students on public.students;
create policy teacher_own_students on public.students for select to authenticated
  using (teacher_id = public.get_teacher_id_for_current_user() and is_archived = false);
create or replace function public.is_my_student(stu uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.students s where s.id = stu and s.is_archived = false and s.teacher_id = public.get_teacher_id_for_current_user()) $$;
create or replace function public.admin_update_account(p_user uuid, p_name text, p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare em text := lower(btrim(p_email));
begin
  if public.get_current_user_role() is distinct from 'admin' then raise exception 'للمشرف فقط'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'بريد غير صالح: %', p_email; end if;
  if exists (select 1 from public.users where lower(email) = em and id <> p_user) then raise exception 'البريد مستخدم لحساب آخر'; end if;
  update public.users set name = btrim(p_name), email = em where id = p_user;
  update auth.users set email = em, updated_at = now() where id = p_user;
  update auth.identities set identity_data = identity_data || jsonb_build_object('email', em) where user_id = p_user and provider = 'email';
end $$;
revoke execute on function public.admin_update_account(uuid, text, text) from anon, public;
grant execute on function public.admin_update_account(uuid, text, text) to authenticated;

-- ===== إضافة لاحقة: الملف الشخصي مع الصورة، ولوحة الشرف مع اسم المعلم =====
alter table public.user_profiles
  add column if not exists phone text, add column if not exists residence text,
  add column if not exists id_type text, add column if not exists id_number text, add column if not exists education text;
create or replace function public.update_my_name(p_name text) returns void language plpgsql security definer set search_path = '' as $$
begin
  if length(btrim(coalesce(p_name, ''))) < 2 then raise exception 'اكتب الاسم'; end if;
  update public.users set name = btrim(p_name) where id = auth.uid();
end $$;
revoke execute on function public.update_my_name(text) from anon, public;
grant execute on function public.update_my_name(text) to authenticated;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg','image/png','image/webp']) on conflict (id) do nothing;
create policy avatars_own_select on storage.objects for select to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_own_insert on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_own_update on storage.objects for update to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_own_delete on storage.objects for delete to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop function if exists public.honor_board(uuid, date, date);
create or replace function public.honor_board(p_plan uuid default null, p_from date default null, p_to date default null)
returns table (student_id uuid, name text, memorized numeric, sessions int, avg_score numeric, teacher_id uuid, teacher_name text)
language sql stable security definer set search_path = '' as $$
  with r as (select pr.student_id, pr.score, pr.memo_from f, pr.memo_to t from public.plan_recitations pr
    where pr.superseded_by is null and pr.status in ('present','makeup') and (p_plan is null or pr.plan_id = p_plan)
      and (p_from is null or pr.rec_date >= p_from) and (p_to is null or pr.rec_date <= p_to)),
  merged as (select student_id, sum(upper(x) - lower(x)) m from (
      select student_id, unnest(range_agg(numrange(least(f,t) - 0.5, greatest(f,t) + 0.5, '[)'))) x from r where f is not null and t is not null and f > 0 group by student_id) q group by student_id)
  select s.id, u.name, coalesce(m.m, 0), (select count(*)::int from r where r.student_id = s.id), (select round(avg(score),2) from r where r.student_id = s.id), s.teacher_id, tu.name
  from public.students s join public.users u on u.id = s.user_id
  left join public.teachers t on t.id = s.teacher_id left join public.users tu on tu.id = t.user_id
  left join merged m on m.student_id = s.id
  where s.is_archived = false and s.status = 'active'
    and (p_plan is null or exists (select 1 from public.plan_assignments a where a.student_id = s.id and a.plan_id = p_plan and a.ended_at is null))
  order by 3 desc, 5 desc nulls last $$;
revoke execute on function public.honor_board(uuid, date, date) from anon, public;
grant execute on function public.honor_board(uuid, date, date) to authenticated;

-- ===== إضافة لاحقة: إشعارات الجوال =====
-- مفاتيح VAPID تُحفظ في app_secrets (لا يقرؤها إلا مفتاح الخدمة). المفتاح الخاص لا يوضع في المستودع:
-- أنشئ مفاتيح جديدة لمشروع المنصة (npx web-push generate-vapid-keys) وضع العام في app.js والخاص هنا.
create table if not exists public.app_secrets (key text primary key, value text not null, updated_at timestamptz not null default now());
alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from anon, authenticated;
-- insert into public.app_secrets (key, value) values ('vapid_public', '<PUBLIC>'), ('vapid_private', '<PRIVATE>'), ('vapid_subject', 'https://<الموقع>/');
alter table public.push_subscriptions add column if not exists last_ok_at timestamptz, add column if not exists fail_count int not null default 0;
-- تشغيل دالة الإرسال send-push كل دقيقة عند وجود إشعارات منتظرة (استبدل <REF> و<ANON_JWT> بقيم المشروع)
create extension if not exists pg_net;
create extension if not exists pg_cron;
-- select cron.schedule('send-push-every-minute', '* * * * *', $$ select net.http_post(url := 'https://<REF>.supabase.co/functions/v1/send-push',
--   headers := '{"Content-Type":"application/json","Authorization":"Bearer <ANON_JWT>"}'::jsonb, body := '{}'::jsonb)
--   where exists (select 1 from public.notifications where channel = 'push' and status = 'queued') $$);
