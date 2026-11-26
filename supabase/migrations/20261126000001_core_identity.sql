-- =====================================================================
-- 0001: الأساسيات، المستخدمون، الأدوار والصلاحيات
-- جمعية سنن التعليمية — منصة التعليم عن بعد
-- =====================================================================

create extension if not exists citext;
create extension if not exists btree_gist;
create extension if not exists pgcrypto;

-- تحديث updated_at تلقائيًا
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- المستخدمون: كل شخص (طالب، معلم، مشرف) مستخدم واحد ببريد فريد
-- ---------------------------------------------------------------------
create table public.app_users (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid unique references auth.users(id) on delete set null,
  email         citext not null unique,
  display_name  text not null,
  phone         text,
  status        text not null default 'active' check (status in ('active', 'disabled')),
  timezone      text not null default 'Asia/Riyadh',
  last_login_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint app_users_email_normalized check (email = lower(btrim(email::text)))
);
create trigger app_users_touch before update on public.app_users
  for each row execute function public.touch_updated_at();

create table public.student_profiles (
  user_id           uuid primary key references public.app_users(id) on delete cascade,
  full_name         text not null,
  gender            text check (gender in ('male', 'female')),
  nationality_code  char(2),
  residence_country char(2),
  residence_city    text,
  birth_date        date,
  id_type           text,
  id_number_enc     bytea,          -- رقم الإثبات مشفّر، لا يظهر إلا للمشرف
  education_level   text,
  quran_parts       numeric(4,1) check (quran_parts between 0 and 30),
  photo_file_id     uuid,
  updated_at        timestamptz not null default now()
);
create trigger student_profiles_touch before update on public.student_profiles
  for each row execute function public.touch_updated_at();

create table public.teacher_profiles (
  user_id     uuid primary key references public.app_users(id) on delete cascade,
  public_name text not null,
  bio         text,
  active      boolean not null default true,
  updated_at  timestamptz not null default now()
);
create trigger teacher_profiles_touch before update on public.teacher_profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- الأدوار والصلاحيات: الصلاحية = دور × نطاق
-- ---------------------------------------------------------------------
create table public.roles (
  key       text primary key,
  name      text not null,
  is_system boolean not null default false
);

create table public.permissions (
  key         text primary key,
  description text not null
);

create table public.role_permissions (
  role_key       text not null references public.roles(key) on delete cascade,
  permission_key text not null references public.permissions(key) on delete cascade,
  primary key (role_key, permission_key)
);

create table public.role_assignments (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.app_users(id) on delete cascade,
  role_key   text not null references public.roles(key),
  scope_type text not null default 'global' check (scope_type in ('global', 'program')),
  scope_id   uuid,
  valid_from timestamptz not null default now(),
  valid_to   timestamptz,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  constraint role_assignments_scope check (
    (scope_type = 'global' and scope_id is null) or (scope_type = 'program' and scope_id is not null)
  ),
  constraint role_assignments_period check (valid_to is null or valid_to > valid_from)
);
create index role_assignments_user_idx on public.role_assignments (user_id);

-- مفاتيح التكامل المستقبلي (الذكاء الاصطناعي وغيره). لا يُخزَّن المفتاح نفسه.
create table public.api_clients (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  key_hash   text not null unique,
  scopes     text[] not null default '{}',
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

-- ---------------------------------------------------------------------
-- بيانات أولية: الأدوار والصلاحيات
-- ---------------------------------------------------------------------
insert into public.roles (key, name, is_system) values
  ('super_admin',     'مشرف عام',     true),
  ('program_admin',   'مشرف برنامج',  true),
  ('assistant',       'مساعد إداري',  true),
  ('teacher',         'معلم',         true),
  ('examiner',        'مختبِر',        true),
  ('student',         'طالب',         true);

insert into public.permissions (key, description) values
  ('programs.manage',     'إنشاء البرامج وتعديل إعداداتها وخططها'),
  ('students.manage',     'إدارة الطلاب والتسجيلات والقبول'),
  ('students.view_pii',   'الاطلاع على البيانات الحساسة مثل رقم الإثبات'),
  ('teachers.manage',     'إدارة المعلمين والإسناد'),
  ('records.write',       'رصد الإنجاز اليومي'),
  ('records.override',    'تعديل الرصد بعد انتهاء المهلة'),
  ('leave.decide',        'اعتماد الاستئذانات'),
  ('discipline.manage',   'إدارة التنبيهات والإنذارات وحالات المتابعة'),
  ('sessions.manage',     'إدارة الفترات والحجوزات وطلبات التغيير'),
  ('exams.manage',        'إدارة بنك الأسئلة والاختبارات'),
  ('exams.grade',         'رصد الاختبارات الشفهية'),
  ('notifications.send',  'إرسال الإعلانات والرسائل الإدارية'),
  ('complaints.manage',   'استقبال الشكاوى ومعالجتها'),
  ('reports.view',        'الاطلاع على التقارير'),
  ('audit.view',          'الاطلاع على سجل الإجراءات'),
  ('roles.manage',        'إدارة الأدوار والصلاحيات'),
  ('import.run',          'تشغيل الاستيراد من الأنظمة السابقة');

-- المشرف العام: كل الصلاحيات
insert into public.role_permissions (role_key, permission_key)
  select 'super_admin', key from public.permissions;

-- مشرف البرنامج: كل شيء داخل برامجه عدا الأدوار
insert into public.role_permissions (role_key, permission_key)
  select 'program_admin', key from public.permissions where key not in ('roles.manage');

insert into public.role_permissions (role_key, permission_key) values
  ('assistant', 'students.manage'), ('assistant', 'discipline.manage'),
  ('assistant', 'sessions.manage'), ('assistant', 'reports.view'),
  ('teacher',   'records.write'),
  ('examiner',  'exams.grade');
