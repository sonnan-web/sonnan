-- توحيد الجنسيات: كل الصيغ (سوري/سورية/سوريا/السوري، أثيوبي/إثيوبية، مصرى…) تُحفظ باسم واحد
-- المفتاح: بلا تشكيل، الهمزات ألف، ى=ي، ة=ه، بلا «ال» في أوله، بلا تاء التأنيث، «يا» في آخره = «ي»
create or replace function public.nat_key(v text) returns text language plpgsql immutable as $$
declare t text;
begin
  if v is null then return null; end if;
  t := lower(btrim(v));
  t := regexp_replace(t, '[ًٌٍَُِّْـ]', '', 'g');
  t := translate(t, 'أإآٱىة', 'اااايه');
  t := regexp_replace(t, '[،,.\-_/():]', ' ', 'g');
  t := regexp_replace(t, '(ال)?جنسيه', ' ', 'g');
  t := btrim(regexp_replace(t, '\s+', ' ', 'g'));
  t := regexp_replace(t, '^ال', '');
  t := regexp_replace(t, 'ه$', '');
  t := regexp_replace(t, 'يا$', 'ي');
  return t;
end $$;

create table if not exists public.nationality_names (
  canonical text not null,
  alias text not null,
  key text generated always as (public.nat_key(alias)) stored,
  primary key (alias)
);
alter table public.nationality_names enable row level security;
drop policy if exists read_all on public.nationality_names;
create policy read_all on public.nationality_names for select to authenticated using (true);
drop policy if exists admin_write on public.nationality_names;
create policy admin_write on public.nationality_names for all to authenticated using ((select public.get_current_user_role()) = 'admin') with check ((select public.get_current_user_role()) = 'admin');

insert into public.nationality_names (canonical, alias)
select c, a from (values
  ('سعودي','سعودي|السعودية|المملكة العربية السعودية|saudi|saudi arabia|ksa'),
  ('مصري','مصري|مصر|egypt|egyptian'),
  ('يمني','يمني|اليمن|yemen|yemeni'),
  ('سوري','سوري|سوريا|سورية|syria|syrian'),
  ('عراقي','عراقي|العراق|iraq|iraqi'),
  ('أردني','أردني|الأردن|jordan|jordanian'),
  ('فلسطيني','فلسطيني|فلسطين|palestine|palestinian'),
  ('لبناني','لبناني|لبنان|lebanon|lebanese'),
  ('كويتي','كويتي|الكويت|kuwait|kuwaiti'),
  ('قطري','قطري|قطر|qatar|qatari'),
  ('بحريني','بحريني|البحرين|bahrain|bahraini'),
  ('إماراتي','إماراتي|الإمارات|الامارات العربية المتحدة|uae|emirati'),
  ('عماني','عماني|عمان|سلطنة عمان|oman|omani'),
  ('سوداني','سوداني|السودان|sudan|sudanese'),
  ('ليبي','ليبي|ليبيا|libya|libyan'),
  ('تونسي','تونسي|تونس|tunisia|tunisian'),
  ('جزائري','جزائري|الجزائر|algeria|algerian'),
  ('مغربي','مغربي|المغرب|morocco|moroccan'),
  ('موريتاني','موريتاني|موريتانيا|mauritania|mauritanian'),
  ('صومالي','صومالي|الصومال|somalia|somali'),
  ('جيبوتي','جيبوتي|djibouti'),
  ('جزر القمر','قمري|جزر القمر|comoros'),
  ('إثيوبي','إثيوبي|إثيوبيا|اثيوبيا|أثيوبيا|ethiopia|ethiopian'),
  ('إريتري','إريتري|إريتريا|eritrea|eritrean'),
  ('كيني','كيني|كينيا|kenya|kenyan'),
  ('تنزاني','تنزاني|تنزانيا|tanzania|tanzanian'),
  ('أوغندي','أوغندي|أوغندا|uganda|ugandan'),
  ('نيجيري','نيجيري|نيجيريا|nigeria|nigerian'),
  ('نيجري','نيجري|النيجر|niger|nigerien'),
  ('تشادي','تشادي|تشاد|chad|chadian'),
  ('مالي','مالي|mali|malian'),
  ('سنغالي','سنغالي|السنغال|senegal|senegalese'),
  ('غامبي','غامبي|غامبيا|gambia|gambian'),
  ('غيني','غيني|غينيا|guinea|guinean'),
  ('غاني','غاني|غانا|ghana|ghanaian'),
  ('بنيني','بنيني|بنين|benin|beninese'),
  ('توغولي','توغولي|توغو|togo|togolese'),
  ('بوركيني','بوركيني|بوركينا فاسو|burkina faso'),
  ('إيفواري','إيفواري|ساحل العاج|كوت ديفوار|ivory coast'),
  ('كاميروني','كاميروني|الكاميرون|cameroon|cameroonian'),
  ('جنوب أفريقي','جنوب أفريقي|جنوب أفريقيا|south africa|south african'),
  ('تركي','تركي|تركيا|turkey|türkiye|turkish'),
  ('إيراني','إيراني|إيران|iran|iranian'),
  ('أفغاني','أفغاني|أفغانستان|afghanistan|afghan'),
  ('باكستاني','باكستاني|باكستان|pakistan|pakistani'),
  ('هندي','هندي|الهند|india|indian'),
  ('بنغلاديشي','بنغلاديشي|بنغلاديش|بنجلاديش|بنجلاديشي|بنغلادش|bangladesh|bangladeshi'),
  ('سريلانكي','سريلانكي|سريلانكا|sri lanka|sri lankan'),
  ('نيبالي','نيبالي|نيبال|nepal|nepali'),
  ('إندونيسي','إندونيسي|إندونيسيا|indonesia|indonesian'),
  ('ماليزي','ماليزي|ماليزيا|malaysia|malaysian'),
  ('فلبيني','فلبيني|الفلبين|philippines|filipino'),
  ('تايلندي','تايلندي|تايلاند|thailand|thai'),
  ('صيني','صيني|الصين|china|chinese'),
  ('أوزبكي','أوزبكي|أوزبكستان|uzbekistan|uzbek'),
  ('طاجيكي','طاجيكي|طاجيكستان|طاجكستان|tajikistan|tajik'),
  ('قرغيزي','قرغيزي|قيرغيزستان|kyrgyzstan|kyrgyz'),
  ('كازاخي','كازاخي|كازاخستان|kazakhstan|kazakh'),
  ('تركمانستاني','تركمانستاني|تركمانستان|turkmenistan'),
  ('أذربيجاني','أذربيجاني|أذربيجان|azerbaijan|azerbaijani'),
  ('روسي','روسي|روسيا|russia|russian'),
  ('شيشاني','شيشاني|الشيشان|chechen'),
  ('ألباني','ألباني|ألبانيا|albania|albanian'),
  ('بوسني','بوسني|البوسنة|البوسنة والهرسك|bosnia|bosnian'),
  ('صربي','صربي|صربيا|serbia|serbian'),
  ('كوسوفي','كوسوفي|كوسوفو|kosovo'),
  ('مقدوني','مقدوني|مقدونيا|macedonia|macedonian'),
  ('بريطاني','بريطاني|بريطانيا|المملكة المتحدة|uk|united kingdom|british'),
  ('فرنسي','فرنسي|فرنسا|france|french'),
  ('ألماني','ألماني|ألمانيا|germany|german'),
  ('هولندي','هولندي|هولندا|netherlands|dutch'),
  ('بلجيكي','بلجيكي|بلجيكا|belgium|belgian'),
  ('سويدي','سويدي|السويد|sweden|swedish'),
  ('أمريكي','أمريكي|أمريكا|امريكي|الولايات المتحدة|usa|us|american'),
  ('كندي','كندي|كندا|canada|canadian'),
  ('أسترالي','أسترالي|أستراليا|australia|australian')
) v(c, list), unnest(string_to_array(list, '|')) a
on conflict (alias) do update set canonical = excluded.canonical;

create or replace function public.canon_nationality(v text) returns text language plpgsql stable set search_path = public as $$
declare k text; r text; w text; s text;
begin
  if v is null or btrim(v) = '' then return null; end if;
  k := public.nat_key(v);
  select canonical into r from nationality_names where key = k limit 1;
  if r is not null then return r; end if;
  -- صيغة بكلمتين مثل «كيني kenyan»: تُجرّب كل كلمة
  foreach w in array string_to_array(k, ' ') loop
    select canonical into r from nationality_names where key = public.nat_key(w) limit 1;
    if r is not null then return r; end if;
  end loop;
  -- غير موجودة في القائمة: إن كانت صفة نسبة (تنتهي بياء النسبة) توحَّد بلا «ال» ولا تأنيث، وإلا تبقى كما كُتبت
  if v ~ '^[؀-ۿ]+$' then
    s := regexp_replace(regexp_replace(regexp_replace(translate(btrim(v), 'ىة', 'يه'), '^ال', ''), 'ه$', ''), 'يا$', 'ي');
    if s ~ 'ي$' then return s; end if;
  end if;
  return btrim(v);
end $$;

create or replace function public.nationality_guard() returns trigger language plpgsql set search_path = public as $$
begin new.nationality := public.canon_nationality(new.nationality); return new; end $$;
drop trigger if exists nationality_canon on public.students;
create trigger nationality_canon before insert or update of nationality on public.students for each row execute function public.nationality_guard();
drop trigger if exists nationality_canon on public.user_profiles;
create trigger nationality_canon before insert or update of nationality on public.user_profiles for each row execute function public.nationality_guard();

update public.students set nationality = nationality where nationality is not null;
update public.user_profiles set nationality = nationality where nationality is not null;

-- ما يظهر للمعلم في «رصد جلسة التسميع»: كل الطلاب، أو طلاب فتراته المسندة إليه فقط
alter table public.teachers add column if not exists record_scope text not null default 'all' check (record_scope in ('all', 'assigned'));

-- روابط إضافية للخطة، وعمود نعم/لا يعرض مقدار نطاق (مثل مقدار الحفظ)
alter table public.program_plans add column if not exists extra_links jsonb not null default '[]'::jsonb;
alter table public.plan_columns add column if not exists shows_column_id uuid references public.plan_columns(id) on delete set null;

-- «لمن تظهر»: إضافة «لا أحد» (عمود للحساب فقط)
alter table public.plan_columns drop constraint if exists plan_columns_executor_check;
alter table public.plan_columns add constraint plan_columns_executor_check check (executor in ('student', 'teacher', 'both', 'info', 'none'));

-- عمود «تفاصيل لمهمة»: يظهر داخل بطاقة مهمة أخرى بلا علامة إنجاز مستقلة
alter table public.plan_columns add column if not exists detail_of uuid references public.plan_columns(id) on delete set null;

-- «تقييم الضبط» منفصل عن «عليها درجة» (الالتزام)، ودالة الالتزام والضبط، ولوحة الشرف بالالتزام
-- (النص الكامل لدالتي plan_commitment و honor_board كما طُبّق في المشروع)
alter table public.plan_columns add column if not exists graded boolean not null default false;
alter table public.plan_columns add column if not exists grade_weight numeric;
update public.plan_columns set graded = counts where graded = false and counts;
-- انظر migration «commitment_and_precision» في Supabase للنص الكامل لـ plan_commitment و honor_board

-- المراحل والاختبارات: الجداول plan_stages, exams, exam_questions, exam_attempts, stage_holds
-- والدوال stage_bounds, sync_stage_holds, close_stage_hold, start_exam, exam_paper, grade_attempt_auto, submit_exam, grade_attempt, oral_result
-- وتحديث plan_commitment لاستبعاد أيام التوقف — انظر migration «stages_and_exams» في Supabase للنص الكامل
-- وجدولة: select cron.schedule('sync-stage-holds', '7 * * * *', 'select public.sync_stage_holds()');

-- إجراءات المشرف: حالة «مفصول»، وخاتمة الحالة، وسجل تواصل متعدد، وإنهاء التحاق الطالب وإعادته
-- انظر migration «supervisor_actions» في Supabase (follow_up_contacts, end_student, reactivate_student)

-- خيارات المرحلة: basis (plan/recitation/execution) و hold_enabled و stop_value، وتحديث stage_bounds — انظر migration «stage_options»

-- الإنجاز والتعثر الموحّدان: plan_columns.is_progress (مهمة الإنجاز) و program_plans.progress_by (من ينفّذ الإنجاز: teacher/student/either/both)
-- والدالة plan_metrics(p_plan, p_from, p_to, p_student) ← iltizam, dabt, ach, ach_days, ach_due, ach_total, ach_left, elapsed, stumbles, stumble_dates
-- و plan_commitment صارت غلافًا لها — انظر migration «plan_metrics» في Supabase للنص الكامل

-- التقدّم بالتنفيذ الفعلي: plan_timeline(p_student, p_plan) يبني مسار كل طالب يومًا بيوم (يوم الخطة، التقدّم، ما بلغه في المهمة الأساسية، التعثر)
-- يتقدّم يوم الخطة بكل جلسة رُصدت فيها المهمة الأساسية (أو تعليم الطالب حسب «لمن تظهر» وتنفيذ الطالب)، ولا يتقدّم في الغياب،
-- وإذا سبق رصدُه أيامًا قادمة تُعدّ منجزة. plan_metrics و sync_stage_holds صارتا مبنيّتين عليه — انظر migrations:
-- plan_timeline_execution, plan_timeline_access, plan_timeline_content_jump, plan_metrics_on_timeline, sync_stage_holds_on_timeline
