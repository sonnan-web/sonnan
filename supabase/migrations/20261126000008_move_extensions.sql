-- =====================================================================
-- 0008: نقل الإضافات خارج المخطط العام (توصية فحص الأمان في Supabase)
-- =====================================================================
create schema if not exists extensions;
alter extension citext set schema extensions;
alter extension btree_gist set schema extensions;
comment on table public.api_clients is 'مفاتيح التكامل: لا وصول من المتصفح إطلاقًا، تُدار من الخادم فقط (لذلك لا سياسات RLS).';
