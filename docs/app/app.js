/* منصة سنن — أدوات مشتركة لكل الصفحات */
(function () {
  'use strict';
  // المشروع التجريبي. عند الانتقال لمشروع المنصة يُغيَّر هذان السطران فقط.
  const SUPABASE_URL = 'https://ijkotzbzpduaqykumqtq.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_0Ug3AHf8CWHpa4N1Hp9TvA_Ls7NMXaS';
  // مفتاح جلسة خاص بهذه المنصة حتى لا يختلط بجلسة الصفحات القديمة على نفس النطاق
  const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, storage: window.localStorage, storageKey: 'sonnan-app-auth' }
  });

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const norm = s => String(s ?? '').replace(/[ً-ْـ]/g, '').replace(/[أإآ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه').replace(/\s+/g, ' ').trim().toLowerCase();
  const fmtNum = (n, d = 0) => n == null || isNaN(n) ? '—' : Number(n).toLocaleString('ar-SA-u-nu-latn', { maximumFractionDigits: d, minimumFractionDigits: 0 });

  // التاريخ بتوقيت مكة
  const todayMakkah = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Riyadh' }).format(new Date());
  const nowMakkahHM = () => new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Riyadh', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date());
  const dowMakkah = () => new Date(todayMakkah() + 'T12:00:00Z').getUTCDay();
  const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
  const daysBetween = (a, b) => Math.round((new Date(b + 'T12:00:00Z') - new Date(a + 'T12:00:00Z')) / 864e5);
  const hijri = iso => { try { return new Intl.DateTimeFormat('ar-SA-u-ca-islamic-umalqura-nu-latn', { day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(iso + 'T12:00:00Z')); } catch (e) { return ''; } };
  const greg = iso => new Intl.DateTimeFormat('ar-SA-u-ca-gregory-nu-latn', { day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(iso + 'T12:00:00Z'));
  const dayName = iso => DAYS[new Date(iso + 'T12:00:00Z').getUTCDay()];
  const DAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
  // عدد أيام العمل بين تاريخين (شاملًا) حسب أيام الخطة
  function workdaysBetween(from, to, workdays) {
    if (!from || !to || to < from) return 0;
    let n = 0, d = from, guard = 0;
    while (d <= to && guard++ < 4000) { if (workdays.includes(new Date(d + 'T12:00:00Z').getUTCDay())) n++; d = addDays(d, 1); }
    return n;
  }

  const STATUS = {
    present: { label: 'حاضر', cls: 'ok', color: 'var(--green)' },
    makeup: { label: 'تعويض', cls: 'gold', color: 'var(--gold)' },
    review_only: { label: 'ربط ومراجعة فقط', cls: 'info', color: 'var(--blue)' },
    excused: { label: 'مستأذن', cls: 'violet', color: 'var(--violet)' },
    absent: { label: 'غائب', cls: 'bad', color: 'var(--red)' },
    none: { label: 'لم يُرصد', cls: 'plain', color: 'var(--slate)' }
  };
  const statusPill = s => { const x = STATUS[s] || STATUS.none; return `<span class="pill ${x.cls}">${x.label}</span>`; };
  const STU_STATUS = { active: ['منتظم', 'ok'], paused: ['موقوف', 'warn'], graduated: ['خاتم', 'info'], withdrawn: ['منسحب', 'bad'] };

  let toastT;
  function toast(msg, bad) { let t = $('#toast'); if (!t) { t = document.createElement('div'); t.id = 'toast'; document.body.appendChild(t); } t.textContent = msg; t.className = 'toast' + (bad ? ' bad' : ''); t.hidden = false; clearTimeout(toastT); toastT = setTimeout(() => t.hidden = true, 3400); }

  // جلب كل الصفوف رغم حد الألف صف
  async function fetchAll(build, size = 1000) {
    let out = [], from = 0;
    for (;;) {
      const { data, error } = await build().range(from, from + size - 1);
      if (error) throw error;
      out = out.concat(data || []);
      if (!data || data.length < size) break;
      from += size;
    }
    return out;
  }

  // التحقق من الدخول والدور
  async function requireRole(roles) {
    const { data: { session } } = await db.auth.getSession();
    if (!session) { location.replace('index.html'); return null; }
    const { data: me, error } = await db.from('users').select('id, name, email, role').eq('id', session.user.id).maybeSingle();
    if (error || !me) { await db.auth.signOut(); location.replace('index.html?e=1'); return null; }
    if (!roles.includes(me.role)) { location.replace(homeOf(me.role)); return null; }
    return me;
  }
  const homeOf = role => role === 'admin' ? 'admin.html' : role === 'teacher' ? 'teacher.html' : 'student.html';
  async function logout() { await db.auth.signOut(); location.replace('index.html'); }

  // جدول قابل للفرز والبحث والتصفية
  // cols: [{key, label, num?, html?(row), val?(row), filter?:true}]
  function dataTable(el, opts) {
    const st = { sortKey: opts.sortKey || null, dir: opts.dir || 1, q: '', filters: {}, shown: opts.pageSize || 100 };
    const valOf = (c, r) => c.val ? c.val(r) : r[c.key];
    function draw() {
      let rows = opts.rows.slice();
      if (st.q) { const q = norm(st.q); rows = rows.filter(r => opts.cols.some(c => norm(valOf(c, r)).includes(q))); }
      Object.entries(st.filters).forEach(([k, v]) => { if (v !== '') { const c = opts.cols.find(c => c.key === k); rows = rows.filter(r => String(valOf(c, r) ?? '') === v); } });
      if (st.sortKey) { const c = opts.cols.find(c => c.key === st.sortKey); rows.sort((a, b) => { let x = valOf(c, a), y = valOf(c, b); if (x == null || x === '') return 1; if (y == null || y === '') return -1; return (c.num ? (x - y) : String(x).localeCompare(String(y), 'ar')) * st.dir; }); }
      const filterCols = opts.cols.filter(c => c.filter);
      el.innerHTML = `<div class="tbl-tools">
          <input type="search" placeholder="بحث…" value="${esc(st.q)}" data-q aria-label="بحث">
          ${filterCols.map(c => { const vals = [...new Set(opts.rows.map(r => valOf(c, r)).filter(v => v != null && v !== ''))].sort((a, b) => String(a).localeCompare(String(b), 'ar')); return `<select data-f="${c.key}" aria-label="${esc(c.label)}"><option value="">${esc(c.label)}: الكل</option>${vals.map(v => `<option value="${esc(v)}"${st.filters[c.key] === String(v) ? ' selected' : ''}>${esc(v)}</option>`).join('')}</select>`; }).join('')}
          ${opts.tools || ''}
        </div>
        <div class="tbl-wrap"><table><thead><tr>${opts.cols.map(c => `<th class="sortable${c.num ? ' num' : ''}" data-s="${c.key}">${esc(c.label)}${st.sortKey === c.key ? `<span class="arr">${st.dir > 0 ? '▲' : '▼'}</span>` : ''}</th>`).join('')}</tr></thead>
        <tbody>${rows.slice(0, st.shown).map((r, i) => `<tr${opts.onRow ? ' class="click"' : ''} data-i="${opts.rows.indexOf(r)}">${opts.cols.map(c => `<td class="${c.num ? 'num' : ''}">${c.html ? c.html(r) : esc(valOf(c, r) ?? '—')}</td>`).join('')}</tr>`).join('') || `<tr><td colspan="${opts.cols.length}" class="muted" style="text-align:center;padding:18px">لا توجد نتائج</td></tr>`}</tbody></table></div>
        <div class="tbl-foot"><span>${rows.length} من ${opts.rows.length}</span>${rows.length > st.shown ? `<button class="btn ghost sm" data-more>عرض المزيد</button>` : ''}</div>`;
      $('[data-q]', el).addEventListener('input', e => { st.q = e.target.value; const pos = e.target.selectionStart; draw(); const i = $('[data-q]', el); i.focus(); i.setSelectionRange(pos, pos); });
      $$('[data-f]', el).forEach(s => s.onchange = () => { st.filters[s.dataset.f] = s.value; draw(); });
      $$('th[data-s]', el).forEach(th => th.onclick = () => { const k = th.dataset.s; if (st.sortKey === k) st.dir *= -1; else { st.sortKey = k; st.dir = opts.cols.find(c => c.key === k).num ? -1 : 1; } draw(); });
      const m = $('[data-more]', el); if (m) m.onclick = () => { st.shown += opts.pageSize || 100; draw(); };
      if (opts.onRow) $$('tbody tr[data-i]', el).forEach(tr => tr.addEventListener('click', e => { if (e.target.closest('button,a,input,select')) return; opts.onRow(opts.rows[+tr.dataset.i]); }));
      if (opts.after) opts.after(el);
    }
    draw();
    return { redraw: draw, setRows(r) { opts.rows = r; draw(); } };
  }

  // زر ملء الشاشة لبطاقة
  function fullscreenBtn(card) {
    const b = document.createElement('button'); b.className = 'full-btn'; b.type = 'button'; b.textContent = 'ملء الشاشة';
    b.onclick = () => { const on = !card.classList.contains('is-full'); card.classList.toggle('is-full', on); b.textContent = on ? 'إغلاق ملء الشاشة' : 'ملء الشاشة'; document.body.style.overflow = on ? 'hidden' : ''; };
    return b;
  }

  // نافذة جانبية
  function drawer(title, html, onMount) {
    closeDrawer();
    const back = document.createElement('div'); back.className = 'drawer-back'; back.id = 'drawerBack';
    const d = document.createElement('aside'); d.className = 'drawer'; d.id = 'drawer'; d.setAttribute('role', 'dialog'); d.setAttribute('aria-label', title);
    d.innerHTML = `<div class="dh"><b>${esc(title)}</b><button class="pillbtn" type="button" id="drawerClose">إغلاق</button></div><div class="db">${html}</div>`;
    document.body.append(back, d);
    back.onclick = closeDrawer; $('#drawerClose').onclick = closeDrawer;
    if (onMount) onMount($('.db', d));
    return d;
  }
  function closeDrawer() { $('#drawer')?.remove(); $('#drawerBack')?.remove(); }
  document.addEventListener('keydown', e => { if (e.key === 'Escape') { closeDrawer(); $$('.is-full').forEach(c => c.querySelector('.full-btn')?.click()); } });

  // تأكيد داخل الصفحة (المتصفح المضمَّن قد يمنع confirm)
  function confirmBox(msg, okLabel = 'تأكيد', danger = true) {
    return new Promise(res => {
      drawer('تأكيد', `<p style="font-size:14px;line-height:1.8">${esc(msg)}</p><div class="row" style="justify-content:flex-start"><button class="btn ${danger ? 'danger' : ''}" id="cbOk">${esc(okLabel)}</button><button class="btn ghost" id="cbNo">إلغاء</button></div>`, root => {
        $('#cbOk', root).onclick = () => { closeDrawer(); res(true); };
        $('#cbNo', root).onclick = () => { closeDrawer(); res(false); };
      });
    });
  }

  // اتحاد نطاقات الحفظ (يقبل الكسور، لا يعد المكرر مرتين)
  function unionCount(ranges) {
    const rs = ranges.filter(r => r[0] != null && r[1] != null && r[0] > 0).map(([a, b]) => [Math.min(a, b) - 0.5, Math.max(a, b) + 0.5]).sort((a, b) => a[0] - b[0]);
    let total = 0, cur = null;
    for (const r of rs) { if (!cur || r[0] > cur[1]) { if (cur) total += cur[1] - cur[0]; cur = r.slice(); } else cur[1] = Math.max(cur[1], r[1]); }
    if (cur) total += cur[1] - cur[0];
    return total;
  }

  // يوم الخطة الحالي للطالب
  function planDayFor(assign, plan, daysCount, onDate) {
    if (!assign || !plan) return null;
    const n = workdaysBetween(assign.start_date, onDate || todayMakkah(), plan.workdays || [0, 1, 2, 3, 4]);
    return Math.min(Math.max(1, (assign.start_day || 1) + n - 1), daysCount || 1);
  }
  const isRecitationDay = (plan, iso) => { if (!plan || plan.recitation_mode === 'none') return false; const d = new Date(iso + 'T12:00:00Z').getUTCDay(); return plan.recitation_mode === 'daily' ? plan.workdays.includes(d) : plan.recitation_days.includes(d); };
  const TASKS = { memo: 'حفظ', link: 'ربط', review: 'مراجعة', repeat: 'تكرار', explain: 'شرح', listen: 'سماع', custom: 'مهمة' };
  const taskName = c => c.task === 'custom' ? (c.task_label || 'مهمة أخرى') : TASKS[c.task];
  // يجمع العمودين المرتبطين في مهمة واحدة
  function groupTasks(cols, filterFn) {
    const out = [], used = {};
    cols.forEach(c => {
      if (used[c.id] || !filterFn(c)) return;
      if (c.pair_column_id) { const o = cols.find(x => x.id === c.pair_column_id); if (o) { used[o.id] = 1; const [a, b] = c.range_role === 'start' ? [c, o] : [o, c]; out.push({ key: a.id, name: taskName(a), from: a, to: b, cols: [a, b], task: a.task, executor: a.executor }); return; } }
      out.push({ key: c.id, name: taskName(c), single: c, cols: [c], task: c.task, executor: c.executor });
    });
    return out;
  }
  function fmtTaskVal(t, vals) {
    if (t.single) { const v = vals?.[t.single.id]; if (v == null || v === '') return null; if (t.single.value_type === 'bool') return v ? 'نعم' : 'لا'; if (t.single.value_type === 'url') return 'رابط'; return String(v); }
    const a = vals?.[t.from.id], b = vals?.[t.to.id];
    if (a == null && b == null) return null;
    return `من ${a ?? '؟'} إلى ${b ?? '؟'}`;
  }

  const icon = name => ({
    home: 'M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z',
    chart: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
    mic: 'M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3zM5 11a7 7 0 0 0 14 0M12 18v3',
    list: 'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01',
    users: 'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21a7 7 0 0 1 14 0M16 3.5a4 4 0 0 1 0 7.5M18 14a6 6 0 0 1 4 7',
    leave: 'M8 2v4M16 2v4M3 10h18M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z',
    alert: 'M12 9v4M12 17h.01M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z',
    exam: 'M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11',
    star: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z',
    plan: 'M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2zM4 21V5M9 7h6M9 11h6',
    teacher: 'M12 3L2 8l10 5 10-5-10-5zM6 10v5c0 2 3 4 6 4s6-2 6-4v-5',
    room: 'M3 18v-6a9 9 0 0 1 18 0v6M21 19a2 2 0 0 1-2 2h-1v-6h3zM3 19a2 2 0 0 0 2 2h1v-6H3z',
    bell: 'M6 16V11a6 6 0 1 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0',
    report: 'M3 3v18h18M7 15l4-4 3 3 5-6',
    user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0',
    book: 'M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2zM4 21V5'
  }[name] || '');
  const svg = name => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${icon(name)}"/></svg>`;

  window.App = { db, $, $$, esc, norm, fmtNum, todayMakkah, nowMakkahHM, dowMakkah, addDays, daysBetween, hijri, greg, dayName, DAYS, workdaysBetween,
    STATUS, statusPill, STU_STATUS, toast, fetchAll, requireRole, homeOf, logout, dataTable, fullscreenBtn, drawer, closeDrawer, confirmBox,
    unionCount, planDayFor, isRecitationDay, TASKS, taskName, groupTasks, fmtTaskVal, svg };
})();
