-- =====================================================================
-- 0002: البرامج والإعدادات المُصدَّرة، الكتب والمجلدات، الخطط والمراحل
-- لا قيمة لائحية مثبّتة في الكود: كل القواعد في program_settings_versions
-- =====================================================================

create table public.programs (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,              -- مثل: sahihayn, zawaid, umdah, bulugh
  name        text not null,
  delivery    text not null default 'remote' check (delivery in ('remote', 'in_person', 'hybrid')),
  status      text not null default 'draft' check (status in ('draft', 'active', 'paused', 'archived')),
  description text,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger programs_touch before update on public.programs
  for each row execute function public.touch_updated_at();

-- إعدادات البرنامج: نسخ لها تاريخ سريان، لا تُعدَّل بعد اعتمادها
create table public.program_settings_versions (
  id             uuid primary key default gen_random_uuid(),
  program_id     uuid not null references public.programs(id) on delete cascade,
  version_no     int not null,
  effective_from date not null,
  settings       jsonb not null check (jsonb_typeof(settings) = 'object'),
  change_note    text,
  status         text not null default 'draft' check (status in ('draft', 'approved')),
  approved_by    uuid references public.app_users(id),
  approved_at    timestamptz,
  created_by     uuid references public.app_users(id),
  created_at     timestamptz not null default now(),
  unique (program_id, version_no),
  constraint psv_approval check ((status = 'approved') = (approved_at is not null))
);
create unique index psv_one_approved_per_day
  on public.program_settings_versions (program_id, effective_from) where status = 'approved';

-- منع تعديل نسخة معتمدة
create or replace function public.forbid_approved_settings_change()
returns trigger language plpgsql as $$
begin
  if old.status = 'approved' then
    raise exception 'نسخة الإعدادات المعتمدة لا تُعدَّل؛ أنشئ نسخة جديدة';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $$;
create trigger psv_immutable before update or delete on public.program_settings_versions
  for each row execute function public.forbid_approved_settings_change();

-- روابط البرنامج (مجموعات، قنوات، نماذج) قابلة للتغيير
create table public.program_links (
  id         uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.programs(id) on delete cascade,
  kind       text not null,                      -- whatsapp_group, telegram, guide, ...
  label      text not null,
  url        text not null,
  audience   text not null default 'students' check (audience in ('students', 'teachers', 'staff', 'public')),
  active     boolean not null default true,
  sort_order int not null default 0
);

-- ---------------------------------------------------------------------
-- الكتب والمجلدات ووحدات القياس
-- ---------------------------------------------------------------------
create table public.books (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  title       text not null,
  author      text,
  unit_kind   text not null default 'hadith' check (unit_kind in ('hadith', 'page', 'line', 'custom')),
  total_units numeric(10,2),
  notes       text
);

create table public.book_volumes (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null references public.books(id) on delete cascade,
  volume_no   int not null,
  title       text,
  first_unit  numeric(10,2) not null,
  last_unit   numeric(10,2) not null,
  -- معامل تحويل الحديث إلى صفحة لهذا المجلد (1.9 / 4.6 / 5.5 ...)
  units_per_page numeric(6,3),
  unique (book_id, volume_no),
  constraint book_volumes_range check (last_unit >= first_unit),
  constraint book_volumes_no_overlap exclude using gist (
    book_id with =, numrange(first_unit, last_unit, '[]') with &&
  )
);

-- خريطة اختيارية: الوحدة ↔ الصفحة، حين يكون التحويل غير خطي
create table public.unit_pages (
  book_id uuid not null references public.books(id) on delete cascade,
  unit_no numeric(10,2) not null,
  page_no numeric(8,2) not null,
  primary key (book_id, unit_no)
);

-- مناهج البرنامج: أي الكتب وبأي ترتيب
create table public.program_curricula (
  id         uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.programs(id) on delete cascade,
  book_id    uuid not null references public.books(id),
  seq        int not null,
  required   boolean not null default true,
  unique (program_id, book_id),
  unique (program_id, seq)
);

-- ---------------------------------------------------------------------
-- الخطط: خطة ← نسخ ← بنود لكل يوم عمل ← مراحل
-- ---------------------------------------------------------------------
create table public.plans (
  id         uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.programs(id) on delete cascade,
  code       text not null,
  name       text not null,                      -- مثل: خطة 3 أحاديث يوميًا
  book_id    uuid references public.books(id),
  active     boolean not null default true,
  unique (program_id, code)
);

create table public.plan_versions (
  id             uuid primary key default gen_random_uuid(),
  plan_id        uuid not null references public.plans(id) on delete cascade,
  version_no     int not null,
  effective_from date not null,
  status         text not null default 'draft' check (status in ('draft', 'approved')),
  notes          text,
  created_at     timestamptz not null default now(),
  unique (plan_id, version_no)
);

-- البند: ما المطلوب في يوم العمل رقم N من الخطة
create table public.plan_items (
  id              uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references public.plan_versions(id) on delete cascade,
  workday_index   int not null check (workday_index > 0),
  kind            text not null default 'memorize' check (kind in ('memorize', 'review', 'link', 'test', 'rest')),
  book_id         uuid references public.books(id),
  volume_no       int,
  from_unit       numeric(10,2),
  to_unit         numeric(10,2),
  label           text,
  unique (plan_version_id, workday_index, kind),
  constraint plan_items_range check (from_unit is null or to_unit is null or to_unit >= from_unit)
);
create index plan_items_lookup on public.plan_items (plan_version_id, workday_index);

create table public.stages (
  id              uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references public.plan_versions(id) on delete cascade,
  seq             int not null,
  name            text not null,
  book_id         uuid references public.books(id),
  volume_no       int,
  from_unit       numeric(10,2) not null,
  to_unit         numeric(10,2) not null,
  requires_exam   boolean not null default false,
  unique (plan_version_id, seq),
  constraint stages_range check (to_unit >= from_unit)
);
