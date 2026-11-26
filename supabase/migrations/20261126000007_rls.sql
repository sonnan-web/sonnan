-- =====================================================================
-- 0007: سياسات أمان الصفوف (RLS) — خط الدفاع الثاني
--
-- المبدأ:
--   * كل الجداول مقفلة افتراضيًا (RLS مفعّل، ولا شيء لـ anon).
--   * القراءة من المتصفح بحسب الدور والنطاق.
--   * الكتابات الحساسة (الرصد، القرارات، الإنذارات، الإشعارات، الاستيراد)
--     تمر عبر دوال الخادم (Edge Functions / RPC) التي تتحقق ثم تكتب وتسجّل.
--   * الكتابة المباشرة من المتصفح مسموحة فقط في: إعدادات البرامج لمن يملك
--     الصلاحية، واشتراكات الإشعارات، وقراءة الإشعار، والاستئذان، والشكوى.
-- =====================================================================

-- تثبيت search_path للدوال السابقة
alter function public.touch_updated_at() set search_path = '';
alter function public.forbid_approved_settings_change() set search_path = '';
alter function public.log_enrollment_status() set search_path = '';
alter function public.guard_daily_records() set search_path = '';
alter function public.enforce_slot_capacity() set search_path = '';
alter function public.forbid_mutation() set search_path = '';

-- ---------------------------------------------------------------------
-- دوال مساعدة (security definer حتى لا تتكرر الـ RLS داخلها)
-- ---------------------------------------------------------------------
create schema if not exists app;
grant usage on schema app to authenticated;

create or replace function app.current_user_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.app_users
  where auth_user_id = auth.uid() and status = 'active'
$$;

create or replace function app.has_permission(perm text, program uuid default null)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.role_assignments ra
    join public.role_permissions rp on rp.role_key = ra.role_key
    where ra.user_id = app.current_user_id()
      and rp.permission_key = perm
      and ra.valid_from <= now()
      and (ra.valid_to is null or ra.valid_to > now())
      and (ra.scope_type = 'global' or (program is not null and ra.scope_id = program))
  )
$$;

create or replace function app.is_staff_of_program(program uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.has_permission('students.manage', program) or app.has_permission('reports.view', program)
$$;

create or replace function app.enrollment_program(enrollment uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select program_id from public.enrollments where id = enrollment
$$;

create or replace function app.owns_enrollment(enrollment uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.enrollments
    where id = enrollment and student_id = app.current_user_id()
  )
$$;

create or replace function app.is_teacher_of(enrollment uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.teacher_assignments
    where enrollment_id = enrollment
      and teacher_id = app.current_user_id()
      and valid_from <= (now() at time zone 'Asia/Riyadh')::date
      and (valid_to is null or valid_to > (now() at time zone 'Asia/Riyadh')::date)
  )
$$;

create or replace function app.can_view_enrollment(enrollment uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.owns_enrollment(enrollment)
      or app.is_teacher_of(enrollment)
      or app.is_staff_of_program(app.enrollment_program(enrollment))
$$;

-- للطاقم فقط (بدون الطالب)
create or replace function app.can_staff_enrollment(enrollment uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.is_teacher_of(enrollment)
      or app.is_staff_of_program(app.enrollment_program(enrollment))
$$;

create or replace function app.plan_program(plan_version uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select p.program_id from public.plan_versions v join public.plans p on p.id = v.plan_id
  where v.id = plan_version
$$;

revoke execute on all functions in schema app from anon, public;
grant execute on all functions in schema app to authenticated;

-- ---------------------------------------------------------------------
-- تفعيل RLS على كل الجداول وسحب صلاحيات anon
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
    execute format('revoke all on public.%I from anon', t.tablename);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- المستخدمون والملفات الشخصية
-- ---------------------------------------------------------------------
create policy app_users_select on public.app_users for select to authenticated
  using (
    id = app.current_user_id()
    or app.has_permission('students.manage')
    or app.has_permission('teachers.manage')
    or exists (select 1 from public.enrollments e
               where e.student_id = app_users.id and app.can_staff_enrollment(e.id))
    or exists (select 1 from public.teacher_profiles tp where tp.user_id = app_users.id and tp.active)
  );

-- رقم الإثبات المشفّر لا يُقرأ من المتصفح إطلاقًا
revoke select on public.student_profiles from authenticated;
grant select (user_id, full_name, gender, nationality_code, residence_country, residence_city,
              birth_date, id_type, education_level, quran_parts, photo_file_id, updated_at)
  on public.student_profiles to authenticated;

create policy student_profiles_select on public.student_profiles for select to authenticated
  using (
    user_id = app.current_user_id()
    or app.has_permission('students.manage')
    or exists (select 1 from public.enrollments e
               where e.student_id = student_profiles.user_id and app.can_staff_enrollment(e.id))
  );

create policy teacher_profiles_select on public.teacher_profiles for select to authenticated
  using (true);

create policy roles_select on public.roles for select to authenticated using (true);
create policy permissions_select on public.permissions for select to authenticated using (true);
create policy role_permissions_select on public.role_permissions for select to authenticated using (true);
create policy role_assignments_select on public.role_assignments for select to authenticated
  using (user_id = app.current_user_id() or app.has_permission('roles.manage'));
-- api_clients: لا سياسة = لا وصول من المتصفح

-- ---------------------------------------------------------------------
-- البرامج والكتب والخطط: قراءة لكل مستخدم مسجّل، كتابة لمن يملك programs.manage
-- ---------------------------------------------------------------------
create policy programs_select on public.programs for select to authenticated using (true);
create policy programs_write on public.programs for all to authenticated
  using (app.has_permission('programs.manage', id))
  with check (app.has_permission('programs.manage', id));

create policy psv_select on public.program_settings_versions for select to authenticated using (true);
create policy psv_write on public.program_settings_versions for all to authenticated
  using (app.has_permission('programs.manage', program_id))
  with check (app.has_permission('programs.manage', program_id));

create policy program_links_select on public.program_links for select to authenticated
  using (audience in ('students', 'public') or app.is_staff_of_program(program_id)
         or (audience = 'teachers' and app.has_permission('records.write')));
create policy program_links_write on public.program_links for all to authenticated
  using (app.has_permission('programs.manage', program_id))
  with check (app.has_permission('programs.manage', program_id));

create policy program_curricula_select on public.program_curricula for select to authenticated using (true);
create policy program_curricula_write on public.program_curricula for all to authenticated
  using (app.has_permission('programs.manage', program_id))
  with check (app.has_permission('programs.manage', program_id));

-- الكتب عامة: تعديلها لمن يملك الصلاحية على مستوى الجمعية
create policy books_select on public.books for select to authenticated using (true);
create policy books_write on public.books for all to authenticated
  using (app.has_permission('programs.manage')) with check (app.has_permission('programs.manage'));
create policy book_volumes_select on public.book_volumes for select to authenticated using (true);
create policy book_volumes_write on public.book_volumes for all to authenticated
  using (app.has_permission('programs.manage')) with check (app.has_permission('programs.manage'));
create policy unit_pages_select on public.unit_pages for select to authenticated using (true);
create policy unit_pages_write on public.unit_pages for all to authenticated
  using (app.has_permission('programs.manage')) with check (app.has_permission('programs.manage'));

create policy plans_select on public.plans for select to authenticated using (true);
create policy plans_write on public.plans for all to authenticated
  using (app.has_permission('programs.manage', program_id))
  with check (app.has_permission('programs.manage', program_id));

create policy plan_versions_select on public.plan_versions for select to authenticated using (true);
create policy plan_versions_write on public.plan_versions for all to authenticated
  using (app.has_permission('programs.manage', app.plan_program(id)))
  with check (app.has_permission('programs.manage',
              (select p.program_id from public.plans p where p.id = plan_id)));

create policy plan_items_select on public.plan_items for select to authenticated using (true);
create policy plan_items_write on public.plan_items for all to authenticated
  using (app.has_permission('programs.manage', app.plan_program(plan_version_id)))
  with check (app.has_permission('programs.manage', app.plan_program(plan_version_id)));

create policy stages_select on public.stages for select to authenticated using (true);
create policy stages_write on public.stages for all to authenticated
  using (app.has_permission('programs.manage', app.plan_program(plan_version_id)))
  with check (app.has_permission('programs.manage', app.plan_program(plan_version_id)));

create policy calendar_select on public.calendar_exceptions for select to authenticated using (true);
create policy calendar_write on public.calendar_exceptions for all to authenticated
  using (app.has_permission('programs.manage', program_id))
  with check (app.has_permission('programs.manage', program_id));

-- ---------------------------------------------------------------------
-- التقديم والتسجيل
-- ---------------------------------------------------------------------
create policy application_forms_select on public.application_forms for select to authenticated using (true);
create policy application_forms_write on public.application_forms for all to authenticated
  using (app.has_permission('programs.manage', program_id))
  with check (app.has_permission('programs.manage', program_id));

create policy applications_select on public.applications for select to authenticated
  using (user_id = app.current_user_id() or app.has_permission('students.manage', program_id));

create policy enrollments_select on public.enrollments for select to authenticated
  using (app.can_view_enrollment(id));

create policy enrollment_status_history_select on public.enrollment_status_history for select to authenticated
  using (app.can_view_enrollment(enrollment_id));
create policy enrollment_plans_select on public.enrollment_plans for select to authenticated
  using (app.can_view_enrollment(enrollment_id));
create policy teacher_assignments_select on public.teacher_assignments for select to authenticated
  using (app.can_view_enrollment(enrollment_id) or teacher_id = app.current_user_id());
create policy eso_select on public.enrollment_setting_overrides for select to authenticated
  using (app.can_staff_enrollment(enrollment_id));

-- ---------------------------------------------------------------------
-- الرصد والمتابعة
-- ---------------------------------------------------------------------
create policy daily_records_select on public.daily_records for select to authenticated
  using (app.can_view_enrollment(enrollment_id));
create policy record_items_select on public.record_items for select to authenticated
  using (exists (select 1 from public.daily_records r
                 where r.id = record_id and app.can_view_enrollment(r.enrollment_id)));
create policy record_assessments_select on public.record_assessments for select to authenticated
  using (exists (select 1 from public.daily_records r
                 where r.id = record_id and app.can_view_enrollment(r.enrollment_id)));

create policy leave_requests_select on public.leave_requests for select to authenticated
  using (app.can_view_enrollment(enrollment_id));
create policy leave_requests_student_insert on public.leave_requests for insert to authenticated
  with check (app.owns_enrollment(enrollment_id) and status = 'pending'
              and decided_by is null and decided_at is null);

create policy discipline_events_select on public.discipline_events for select to authenticated
  using (app.can_view_enrollment(enrollment_id));
-- حالات المتابعة ومحاضر التواصل: للطاقم فقط
create policy follow_up_cases_select on public.follow_up_cases for select to authenticated
  using (app.has_permission('discipline.manage', app.enrollment_program(enrollment_id))
         or assignee_id = app.current_user_id());
create policy case_contacts_select on public.case_contacts for select to authenticated
  using (exists (select 1 from public.follow_up_cases c
                 where c.id = case_id
                   and (app.has_permission('discipline.manage', app.enrollment_program(c.enrollment_id))
                        or c.assignee_id = app.current_user_id())));

create policy eds_select on public.enrollment_day_status for select to authenticated
  using (app.can_view_enrollment(enrollment_id));

-- ---------------------------------------------------------------------
-- الفترات والاختبارات
-- ---------------------------------------------------------------------
create policy slots_select on public.slots for select to authenticated using (active or teacher_id = app.current_user_id()
  or app.has_permission('sessions.manage'));
create policy slot_programs_select on public.slot_programs for select to authenticated using (true);
create policy slot_bookings_select on public.slot_bookings for select to authenticated
  using (app.can_view_enrollment(enrollment_id)
         or exists (select 1 from public.slots s where s.id = slot_id and s.teacher_id = app.current_user_id()));
create policy bcr_select on public.booking_change_requests for select to authenticated
  using (app.can_view_enrollment(enrollment_id));
create policy session_occurrences_select on public.session_occurrences for select to authenticated using (true);

-- بنك الأسئلة لا يُقرأ من المتصفح للطلاب (يُقدَّم السؤال عبر الخادم أثناء المحاولة)
create policy questions_select on public.questions for select to authenticated
  using (app.has_permission('exams.manage', program_id) or app.has_permission('exams.grade', program_id));
create policy exam_templates_select on public.exam_templates for select to authenticated using (true);
create policy exam_forms_select on public.exam_forms for select to authenticated
  using (app.has_permission('exams.manage') or app.has_permission('exams.grade'));
create policy exam_form_questions_select on public.exam_form_questions for select to authenticated
  using (app.has_permission('exams.manage') or app.has_permission('exams.grade'));
create policy exam_appointments_select on public.exam_appointments for select to authenticated
  using (app.can_view_enrollment(enrollment_id) or examiner_id = app.current_user_id());
create policy exam_attempts_select on public.exam_attempts for select to authenticated
  using (app.can_view_enrollment(enrollment_id) or graded_by = app.current_user_id());
create policy attempt_answers_select on public.attempt_answers for select to authenticated
  using (exists (select 1 from public.exam_attempts a
                 where a.id = attempt_id and app.can_staff_enrollment(a.enrollment_id)));
create policy attempt_events_select on public.attempt_events for select to authenticated
  using (exists (select 1 from public.exam_attempts a
                 where a.id = attempt_id and app.can_staff_enrollment(a.enrollment_id)));
create policy stage_progress_select on public.stage_progress for select to authenticated
  using (app.can_view_enrollment(enrollment_id));

-- ---------------------------------------------------------------------
-- الإشعارات
-- ---------------------------------------------------------------------
create policy notification_templates_select on public.notification_templates for select to authenticated
  using (app.has_permission('notifications.send', program_id));
create policy notification_events_select on public.notification_events for select to authenticated
  using (app.has_permission('notifications.send', program_id));

create policy notifications_select on public.notifications for select to authenticated
  using (recipient_id = app.current_user_id());
-- الطالب يعلّم الإشعار كمقروء فقط
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy notifications_mark_read on public.notifications for update to authenticated
  using (recipient_id = app.current_user_id())
  with check (recipient_id = app.current_user_id());

create policy announcements_select on public.announcements for select to authenticated
  using (publish_at <= now() and (expires_at is null or expires_at > now())
         or app.has_permission('notifications.send', program_id));

create policy push_subscriptions_own on public.push_subscriptions for all to authenticated
  using (user_id = app.current_user_id())
  with check (user_id = app.current_user_id());

-- ---------------------------------------------------------------------
-- الشكاوى والملفات
-- ---------------------------------------------------------------------
create policy complaints_select on public.complaints for select to authenticated
  using (submitter_id = app.current_user_id()
         or app.has_permission('complaints.manage', program_id));
create policy complaints_insert on public.complaints for insert to authenticated
  with check (submitter_id = app.current_user_id() and status = 'new' and assignee_id is null);
create policy complaint_actions_select on public.complaint_actions for select to authenticated
  using (exists (select 1 from public.complaints c where c.id = complaint_id
                 and ((c.submitter_id = app.current_user_id() and visible_to_submitter)
                      or app.has_permission('complaints.manage', c.program_id))));

create policy files_select on public.files for select to authenticated
  using (owner_id = app.current_user_id() or app.has_permission('students.manage'));

-- ---------------------------------------------------------------------
-- السجل والاستيراد والتقارير
-- ---------------------------------------------------------------------
create policy audit_log_select on public.audit_log for select to authenticated
  using (app.has_permission('audit.view'));
create policy import_batches_select on public.import_batches for select to authenticated
  using (app.has_permission('import.run'));
create policy import_rows_select on public.import_rows for select to authenticated
  using (app.has_permission('import.run'));
create policy report_snapshots_select on public.report_snapshots for select to authenticated
  using (app.has_permission('reports.view', program_id)
         or (kind = 'honor_board'));   -- لوحة الشرف معروضة للطلاب
