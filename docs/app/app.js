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
  // الخروج يمسح الجلسة من الجهاز دائمًا حتى لو فشل طلب الخادم (مثل جلسة منتهية)، وإلا تعيد صفحة الدخول المستخدم إلى لوحته
  async function logout() {
    try { await Promise.race([db.auth.signOut(), new Promise(r => setTimeout(r, 4000))]); } catch (e) {}
    try { await db.auth.signOut({ scope: 'local' }); } catch (e) {}
    try { Object.keys(localStorage).filter(k => k === 'sonnan-app-auth' || k.startsWith('sonnan-app-auth') || k.startsWith('sb-')).forEach(k => localStorage.removeItem(k)); } catch (e) {}
    location.replace('index.html?out=1');
  }

  // جدول قابل للفرز والبحث والتصفية
  // cols: [{key, label, num?, html?(row), val?(row), filter?:true}]
  function dataTable(el, opts) {
    const st = { sortKey: opts.sortKey || null, dir: opts.dir || 1, q: '', filters: {}, shown: opts.pageSize || 100 };
    const valOf = (c, r) => c.val ? c.val(r) : r[c.key];
    function draw() {
      let rows = opts.rows.slice();
      if (st.q) { const q = norm(st.q); rows = rows.filter(r => opts.cols.some(c => norm(valOf(c, r)).includes(q))); }
      Object.entries(st.filters).forEach(([k, v]) => { if (v !== '') { const c = opts.cols.find(c => c.key === k); rows = rows.filter(r => String(valOf(c, r) ?? '') === v); } });
      st.last = rows;
      if (st.sortKey) { const c = opts.cols.find(c => c.key === st.sortKey) || { key: st.sortKey, num: true }; rows.sort((a, b) => { let x = valOf(c, a), y = valOf(c, b); if (x == null || x === '') return 1; if (y == null || y === '') return -1; return (c.num ? (x - y) : String(x).localeCompare(String(y), 'ar')) * st.dir; }); }
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
    return { redraw: draw, setRows(r) { opts.rows = r; draw(); }, getRows: () => st.last || opts.rows };
  }

  // تصدير صفوف إلى ملف إكسل: cols = [[العنوان, دالة القيمة], ...]
  function exportXlsx(fileName, sheetName, cols, rows) {
    if (!window.XLSX) return toast('أداة الإكسل لم تُحمَّل بعد، أعد المحاولة', true);
    const aoa = [cols.map(c => c[0]), ...rows.map(r => cols.map(c => { const v = c[1](r); return v == null ? '' : v; }))];
    const ws = XLSX.utils.aoa_to_sheet(aoa);
    ws['!cols'] = cols.map(c => ({ wch: Math.max(10, String(c[0]).length + 4) }));
    ws['!views'] = [{ RTL: true }];
    const wb = XLSX.utils.book_new(); wb.Workbook = { Views: [{ RTL: true }] };
    XLSX.utils.book_append_sheet(wb, ws, sheetName.slice(0, 31));
    XLSX.writeFile(wb, fileName + '.xlsx');
    toast('صُدّر ' + rows.length + ' صف');
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
  // مقدار النطاق الذي يعرضه عمود نعم/لا (مثل «من 10 إلى 11» لمقدار الحفظ)، يحتاج أعمدة الخطة
  function taskAmount(t, vals, cols) {
    const sc = t.single?.shows_column_id && cols?.find(c => c.id === t.single.shows_column_id); if (!sc) return null;
    const ec = cols.find(c => c.id === sc.pair_column_id); const a = vals?.[sc.id], b = ec ? vals?.[ec.id] : null;
    return a == null && b == null ? null : `من ${a ?? '؟'} إلى ${b ?? '؟'}`;
  }
  function fmtTaskVal(t, vals) {
    if (t.single) { const v = vals?.[t.single.id]; if (v == null || v === '') return null; if (t.single.value_type === 'bool') return v ? 'نعم' : null; if (t.single.value_type === 'url') return 'رابط'; return String(v); }
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
    book: 'M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2zM4 21V5',
    edit: 'M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4',
    calendar: 'M4 6a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v14H4zM4 10h16M8 3v4M16 3v4M8 14h2M14 14h2M8 17h2',
    file: 'M6 3h9l4 4v14H6zM14 3v5h5M9 12h7M9 16h7',
    key: 'M15 3a6 6 0 1 1-5.3 8.8L3 18.5V21h3v-2h2v-2h2l1.2-1.2A6 6 0 0 1 15 3zM16.5 7.5h.01',
    archive: 'M3 4h18v4H3zM5 8v12h14V8M10 12h4',
    restore: 'M4 12a8 8 0 1 0 2.5-5.8M4 4v5h5'
  }[name] || '');
  const svg = name => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${icon(name)}"/></svg>`;

  // ===== رسوم مشتركة =====
  const PALETTE = ['var(--teal)', 'var(--gold)', 'var(--blue)', 'var(--violet)', 'var(--green)', 'var(--orange)', 'var(--red)', 'var(--slate)'];
  function donut(parts, centerLabel) {
    parts = parts.filter(p => p[1] > 0);
    const total = parts.reduce((a, p) => a + p[1], 0);
    let acc = 0;
    const grad = total ? parts.map(([, v, c], i) => { const a = acc / total * 360; acc += v; return `${c || PALETTE[i % PALETTE.length]} ${a}deg ${acc / total * 360}deg`; }).join(',') : 'var(--track) 0deg 360deg';
    return `<div class="donut-wrap"><div class="donut" style="background:conic-gradient(${grad})"><div class="mid"><b>${fmtNum(total)}</b><span>${esc(centerLabel)}</span></div></div>
      <div class="legend">${parts.map(([l, v, c], i) => `<div class="lg"><i style="background:${c || PALETTE[i % PALETTE.length]}"></i><em title="${esc(l)}">${esc(l)}</em><span class="n">${fmtNum(v)}</span><span class="p">${total ? Math.round(v / total * 100) : 0}٪</span></div>`).join('') || '<div class="muted small">لا توجد بيانات</div>'}</div></div>`;
  }
  // يجمع القيم ويُبقي الأكثر تكرارًا ويضم الباقي في «أخرى»
  function tally(values, keep = 6, emptyLabel = 'غير محدد') {
    const m = {}; values.forEach(v => { const k = (v == null || String(v).trim() === '') ? emptyLabel : String(v).trim(); m[k] = (m[k] || 0) + 1; });
    const arr = Object.entries(m).sort((a, b) => b[1] - a[1]);
    if (arr.length <= keep + 1) return arr;
    const top = arr.slice(0, keep), rest = arr.slice(keep).reduce((a, x) => a + x[1], 0);
    return [...top, ['أخرى', rest]];
  }

  // ===== أيقونات الشريط العلوي: الملف الشخصي، الإشعارات، الخروج =====
  const ICON = {
    user: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>',
    bell: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 16V11a6 6 0 1 1 12 0v5l2 2H4z"/><path d="M10 20a2 2 0 0 0 4 0"/></svg>',
    logout: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4"/><path d="M14 4v16"/><path d="M10 12H3"/><path d="M6 9l-3 3 3 3"/></svg>'
  };
  async function unreadCount() { const { count } = await db.from('notifications').select('id', { count: 'exact', head: true }).eq('channel', 'inbox').is('read_at', null); return count || 0; }
  async function topIcons(container, { profileHash = 'profile' } = {}) {
    container.innerHTML = `<a class="icbtn" href="#${profileHash}" title="ملفي الشخصي" aria-label="ملفي الشخصي">${ICON.user}</a>
      <button class="icbtn" type="button" id="bellBtn" title="الإشعارات" aria-label="الإشعارات">${ICON.bell}<span class="dotn" id="bellN" hidden></span></button>
      <button class="icbtn" type="button" id="outBtn" title="تسجيل الخروج" aria-label="تسجيل الخروج">${ICON.logout}</button>`;
    $('#outBtn', container).onclick = logout;
    $('#bellBtn', container).onclick = () => openInbox();
    refreshBell();
  }
  async function refreshBell() { const n = await unreadCount(); const b = $('#bellN'); if (b) { b.textContent = n > 99 ? '99+' : n; b.hidden = !n; } }
  async function openInbox() {
    const { data } = await db.from('notifications').select('*').eq('channel', 'inbox').order('created_at', { ascending: false }).limit(150);
    drawer('الإشعارات', `<div class="row" style="justify-content:flex-end"><button class="btn ghost sm" id="inAll">تعليم الكل كمقروء</button></div>
      <div class="card">${(data || []).map(n => `<div class="inbox-item${n.read_at ? ' read' : ''}" data-id="${n.id}"><span class="dot"></span><div><div class="row"><b>${esc(n.title)}</b><span class="small muted">${greg(n.created_at.slice(0, 10))}</span></div><p class="small" style="margin-top:3px;line-height:1.8">${esc(n.body)}</p></div></div>`).join('') || '<div class="empty">لا توجد إشعارات</div>'}</div>`, root => {
      const mark = async ids => { if (!ids.length) return; await db.from('notifications').update({ read_at: new Date().toISOString() }).in('id', ids); ids.forEach(id => $(`.inbox-item[data-id="${id}"]`, root)?.classList.add('read')); refreshBell(); };
      $$('.inbox-item:not(.read)', root).forEach(i => i.onclick = () => mark([i.dataset.id]));
      $('#inAll', root).onclick = () => mark((data || []).filter(n => !n.read_at).map(n => n.id));
    });
  }

  // ===== الملف الشخصي مع الصورة (للمعلم والطالب) =====
  const GENDERS = ['ذكر', 'أنثى'], ID_TYPES = ['هوية وطنية', 'إقامة', 'جواز سفر', 'أخرى'];
  async function resizeImage(file, max = 320) {
    const url = URL.createObjectURL(file);
    try {
      const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = url; });
      const k = Math.min(1, max / Math.max(img.width, img.height));
      const c = document.createElement('canvas'); c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      return await new Promise(res => c.toBlob(res, 'image/jpeg', 0.85));
    } finally { URL.revokeObjectURL(url); }
  }
  // seed: قيم أولية من سجل الطالب عند خلو الملف
  async function profileSection(el, me, { seed = {}, extra = false } = {}) {
    const { data: p0 } = await db.from('user_profiles').select('*').eq('id', me.id).maybeSingle();
    const p = Object.assign({}, seed, Object.fromEntries(Object.entries(p0 || {}).filter(([, v]) => v != null && v !== '')));
    const f = (id, label, val, type = 'text', more = '') => `<label class="f" for="${id}">${label}<input id="${id}" type="${type}" value="${esc(val ?? '')}" ${more}></label>`;
    el.innerHTML = `<div class="sec-h" style="--c:var(--gold)"><b>ملفي الشخصي</b><span>${esc(me.email)}</span></div>
      <div class="grid">
        <div class="card span4" style="align-items:center;text-align:center;gap:10px">
          <div class="avatar-lg" id="avBox">${p.avatar_url ? `<img src="${esc(p.avatar_url)}" alt="صورتي">` : esc((me.name || '؟').trim().charAt(0))}</div>
          <b>${esc(me.name)}</b><span class="hint">${me.role === 'teacher' ? 'معلم' : 'طالب'}</span>
          <label class="btn ghost sm" for="avFile" style="cursor:pointer">${p.avatar_url ? 'تغيير الصورة' : 'إضافة صورة'}</label><input id="avFile" type="file" accept="image/*" hidden>
          ${p.avatar_url ? '<button class="btn danger sm" id="avDel" type="button">حذف الصورة</button>' : ''}
        </div>
        <div class="card span8"><div class="head"><h3>بياناتي</h3><span class="hint">تستطيع تعديلها متى شئت</span></div>
          <div class="g2">
            ${f('pfName', 'الاسم', me.name)}${f('pfEmail', 'البريد الإلكتروني <span class="hint">يغيّره المشرف</span>', me.email, 'email', 'dir="ltr" disabled')}
            ${f('pfPhone', 'رقم الجوال', p.phone, 'tel', 'dir="ltr"')}
            <label class="f" for="pfGender">الجنس<select id="pfGender"><option value="">—</option>${GENDERS.map(g => `<option${p.gender === g ? ' selected' : ''}>${g}</option>`).join('')}</select></label>
            ${f('pfNat', 'الجنسية', p.nationality)}${f('pfRes', 'مكان الإقامة', p.residence)}
            <label class="f" for="pfIdT">نوع الإثبات<input id="pfIdT" type="text" list="pfIdTypes" value="${esc(p.id_type ?? '')}"><datalist id="pfIdTypes">${ID_TYPES.map(t => `<option value="${t}">`).join('')}</datalist></label>
            ${f('pfIdN', 'رقم الإثبات', p.id_number, 'text', 'dir="ltr"')}
            ${f('pfBirth', 'تاريخ الميلاد', p.birth_date, 'date')}${f('pfEdu', 'التعليم', p.education)}
            ${f('pfQ', 'حفظ القرآن', p.quran_memorization, 'text', 'placeholder="مثال: 15 جزءًا"')}
            ${extra ? f('pfQual', 'المؤهل', p.qualifications) + f('pfWork', 'جهة العمل', p.workplace) : ''}
          </div>
          ${extra ? `<label class="f" for="pfBio" style="margin-top:8px">نبذة<textarea id="pfBio">${esc(p.bio ?? '')}</textarea></label>` : ''}
          <button class="btn" id="pfSave" style="margin-top:10px">حفظ البيانات</button></div>
        <div class="card span12 c-red"><div class="head"><h3>تغيير كلمة المرور</h3></div><div class="g2"><label class="f" for="pfPw">كلمة المرور الجديدة <span class="hint">8 أحرف على الأقل</span><input id="pfPw" type="password" dir="ltr" autocomplete="new-password"></label></div><button class="btn" id="pfPwGo" style="margin-top:10px;justify-self:start">تغيير</button></div>
      </div>`;
    const v = id => $('#' + id, el)?.value.trim() || null;
    $('#pfSave', el).onclick = async () => {
      const b = $('#pfSave', el); b.disabled = true;
      try {
        const name = v('pfName');
        if (name && name !== me.name) { const { error } = await db.rpc('update_my_name', { p_name: name }); if (error) throw error; me.name = name; }
        const row = { id: me.id, phone: v('pfPhone'), gender: v('pfGender'), nationality: v('pfNat'), residence: v('pfRes'), id_type: v('pfIdT'), id_number: v('pfIdN'), birth_date: v('pfBirth'), education: v('pfEdu'), quran_memorization: v('pfQ'), updated_at: new Date().toISOString() };
        if (extra) Object.assign(row, { qualifications: v('pfQual'), workplace: v('pfWork'), bio: v('pfBio') });
        const { error } = await db.from('user_profiles').upsert(row); if (error) throw error;
        toast('حُفظت بياناتك');
      } catch (e) { toast(e.message || String(e), true); }
      b.disabled = false;
    };
    $('#pfPwGo', el).onclick = async () => { const pw = $('#pfPw', el).value; if (pw.length < 8) return toast('8 أحرف على الأقل', true); const { error } = await db.auth.updateUser({ password: pw }); if (error) return toast(error.message, true); $('#pfPw', el).value = ''; toast('تغيّرت كلمة المرور'); };
    $('#avFile', el).onchange = async e => {
      const file = e.target.files[0]; if (!file) return;
      try {
        const blob = await resizeImage(file);
        const path = `${me.id}/avatar-${Date.now()}.jpg`;
        const up = await db.storage.from('avatars').upload(path, blob, { contentType: 'image/jpeg', upsert: true }); if (up.error) throw up.error;
        const url = db.storage.from('avatars').getPublicUrl(path).data.publicUrl;
        const { error } = await db.from('user_profiles').upsert({ id: me.id, avatar_url: url, updated_at: new Date().toISOString() }); if (error) throw error;
        if (p.avatar_url) { const old = p.avatar_url.split('/avatars/')[1]; if (old) db.storage.from('avatars').remove([old]); }
        toast('حُفظت الصورة'); profileSection(el, me, { seed, extra });
      } catch (err) { toast('لم تُرفع الصورة: ' + (err.message || err), true); }
    };
    $('#avDel', el) && ($('#avDel', el).onclick = async () => { const old = p.avatar_url.split('/avatars/')[1]; if (old) await db.storage.from('avatars').remove([old]); await db.from('user_profiles').upsert({ id: me.id, avatar_url: null }); toast('حُذفت الصورة'); profileSection(el, me, { seed, extra }); });
  }

  // ===== نموذج رصد جلسة التسميع (مشترك: صفحة المعلم، نافذة الغرف، لوحة المشرف) =====
  // ctx: { stu:{id,name}, assign, P:{...plan, cols:[], days:{n:day}}, roomId, roomName, teacherId, meId,
  //        teachers?:[{id,name}] (للمشرف: من رصد), canEdit(r), teacherName(id), onSaved(), layout:'wide'|'stack' }
  function recordWidget(container, ctx) {
    const S = { status: 'present', ded: {}, editing: null, makeup: null, draft: null, notes: null, hist: [], shown: 5, teacherId: ctx.teacherId || null };
    const TODAY = todayMakkah();
    container.innerHTML = `<div class="rw ${ctx.layout === 'stack' ? 'rw-stack' : ''}"><div class="rw-form"></div><div class="rw-hist"></div></div>`;
    const fa = $('.rw-form', container), ha = $('.rw-hist', container);
    async function loadHist() {
      const { data } = await db.from('plan_recitations').select('*').eq('student_id', ctx.stu.id).is('superseded_by', null).order('rec_date', { ascending: false }).order('created_at', { ascending: false }).limit(60);
      S.hist = data || [];
    }
    function drawHist() {
      const list = S.hist.slice(0, S.shown);
      ha.innerHTML = `<div class="card c-blue"><div class="head"><h3>آخر ما رُصد للطالب</h3><span class="hint">${S.hist.length ? S.hist.length + (S.hist.length >= 60 ? '+' : '') + ' سجل' : ''}</span></div>
        ${list.length ? list.map(r => `<div class="hist">
          <div class="row"><b>${dayName(r.rec_date)} ${greg(r.rec_date)}</b>${statusPill(r.status)}</div>
          <div class="small muted">${r.memo_from ? 'الحفظ: ' + +r.memo_from + '–' + +r.memo_to + ' · ' : ''}${r.score != null ? 'الدرجة: ' + fmtNum(r.score, 2) : ''}${r.makes_up_date ? ' · تعويض عن ' + greg(r.makes_up_date) : ''}${ctx.teacherName ? ' · ' + esc(ctx.teacherName(r.teacher_id) || '') : ''}${r.notes ? ' · ' + esc(r.notes) : ''}</div>
          ${ctx.canEdit(r) ? `<div class="row" style="justify-content:flex-start;gap:6px"><button class="btn ghost sm" data-edit="${r.id}" type="button">تعديل</button>${ctx.canDelete ? `<button class="btn danger sm" data-del="${r.id}" type="button">حذف</button>` : ''}</div>` : `<div class="hint">${esc(ctx.lockReason?.(r) || 'رصده معلم آخر')}</div>`}</div>`).join('') : '<div class="empty">لا يوجد رصد سابق</div>'}
        ${S.hist.length > S.shown ? `<button class="btn ghost block sm" id="rwMore" type="button" style="margin-top:8px">إظهار المزيد</button>` : ''}</div>`;
      $$('[data-edit]', ha).forEach(b => b.onclick = () => startEdit(b.dataset.edit));
      $$('[data-del]', ha).forEach(b => b.onclick = () => ctx.onDelete && ctx.onDelete(S.hist.find(x => x.id === b.dataset.del), async () => { await loadHist(); drawHist(); }));
      $('#rwMore', ha) && ($('#rwMore', ha).onclick = () => { S.shown += 5; drawHist(); });
    }
    function startEdit(id) {
      const r = S.hist.find(x => x.id === id); if (!r) return;
      S.editing = r; S.status = r.status; S.ded = { ...(r.deductions || {}) }; S.makeup = r.makes_up_date; S.draft = null; S.notes = null; S.teacherId = r.teacher_id || S.teacherId;
      drawForm(); fa.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    function drawForm() {
      const { stu, assign: a, P } = ctx;
      if (!a || !P) { fa.innerHTML = '<div class="card c-red"><div class="error" style="margin:0">لم تُسند للطالب خطة بعد، فلا يظهر نموذج الرصد. اطلب من المشرف إسناد خطة له.</div></div>'; return; }
      if (P.recitation_mode === 'none') { fa.innerHTML = `<div class="card"><div class="hintbox">خطة الطالب «${esc(P.name)}» بلا تسميع، فلا يُرصد له تسميع.</div></div>`; return; }
      const nDays = Object.keys(P.days).length;
      const dayN = planDayFor(a, P, nDays);
      const recDay = isRecitationDay(P, TODAY);
      const recDays = P.recitation_mode === 'daily' ? P.workdays : P.recitation_days;
      const mkWin = P.discipline_rules?.makeup_within_days ?? 14;
      const done = new Set(S.hist.filter(r => ['present', 'makeup', 'review_only', 'excused'].includes(r.status)).map(r => r.rec_date));
      S.hist.filter(r => r.makes_up_date).forEach(r => done.add(r.makes_up_date));
      const missed = [];
      for (let i = 1, d = addDays(TODAY, -1); i <= Math.max(mkWin, 1) && d >= a.start_date; i++, d = addDays(d, -1)) if (isRecitationDay(P, d) && !done.has(d)) missed.push(d);
      const ed = S.editing, st = S.status;
      const targetDayN = st === 'makeup' && S.makeup ? planDayFor(a, P, nDays, S.makeup) : dayN;
      const day = P.days[targetDayN];
      const vals = Object.assign({}, ed ? (ed.vals || {}) : (day?.vals || {}), S.draft || {});
      const tTasks = groupTasks(P.cols, c => c.executor === 'teacher' || c.executor === 'both');
      const refTasks = groupTasks(P.cols, c => c.executor === 'info');
      const showFields = ['present', 'makeup', 'review_only'].includes(st);
      const reviewOnly = st === 'review_only';
      const R = P.score_rules || { max: 10, deductions: [] };
      const score = Math.max(0, (R.max || 0) - (R.deductions || []).reduce((x, d) => x + (S.ded[d.key] || 0) * (+d.value || 0), 0));
      const field = c => {
        const v = vals[c.id];
        if (c.value_type === 'bool') return `<label class="chips"><label><input type="checkbox" data-c="${c.id}"${v ? ' checked' : ''}>${esc(c.header)}</label></label>`;
        return `<label class="f small">${esc(c.header)}<input data-c="${c.id}" type="${c.value_type === 'number' ? 'number' : 'text'}" ${c.value_type === 'number' ? 'step="0.5" inputmode="decimal"' : ''} value="${esc(v ?? '')}"></label>`;
      };
      fa.innerHTML = `<div class="card c-teal">
        <div class="row"><div><h2>${esc(stu.name)}</h2><p class="small muted">${esc(P.name)}${ctx.roomName ? ' · الفترة: ' + esc(ctx.roomName) : ''}</p></div>
          <div style="text-align:left"><span class="pill gold">اليوم ${dayN} من الخطة</span><div class="hint" style="margin-top:3px">${recDay ? 'اليوم يوم تسميع' : 'اليوم ليس من أيام التسميع (' + recDays.map(i => DAYS[i]).join('، ') + ')'}</div></div></div>
        ${ed ? `<div class="hintbox" style="margin-top:8px">تعدّل رصد يوم ${greg(ed.rec_date)}. يُحفظ التعديل سجلًا جديدًا ويبقى القديم في التاريخ. <button class="btn ghost sm" id="rwCancelEdit" type="button">إلغاء التعديل</button></div>` : ''}
        ${ctx.teachers ? `<label class="f" for="rwT" style="margin-top:10px">المعلم الذي سمّع<select id="rwT">${ctx.teachers.map(t => `<option value="${t.id}"${t.id === S.teacherId ? ' selected' : ''}>${esc(t.name)}</option>`).join('')}</select></label>` : ''}
        <div style="margin-top:10px"><b class="small">حالة الطالب</b><div class="seg" style="margin-top:6px">${['present', 'makeup', 'review_only', 'excused', 'absent'].map(k => `<button type="button" data-st="${k}" aria-pressed="${st === k}">${STATUS[k].label}</button>`).join('')}</div></div>
        ${st === 'makeup' ? `<label class="f" for="rwMk" style="margin-top:10px">تعويض عن يوم <span class="hint">أيام تسميع فاتته خلال ${mkWin} يومًا ولم تُعوَّض</span><select id="rwMk">${(ed?.makes_up_date && !missed.includes(ed.makes_up_date) ? [ed.makes_up_date] : []).concat(missed).map(d => `<option value="${d}"${S.makeup === d ? ' selected' : ''}>${dayName(d)} ${greg(d)}</option>`).join('') || '<option value="">لا توجد أيام فائتة</option>'}</select></label>` : ''}
        ${showFields ? `<div class="stack" style="margin-top:12px">
          ${tTasks.filter(t => !reviewOnly || t.task !== 'memo').map(t => `<div class="task-f"><div class="row"><b>${esc(t.name)}</b><span class="hint">المقرر${st === 'makeup' ? ' ليوم التعويض' : ''}: ${esc(fmtTaskVal(t, day?.vals) ?? '—')}</span></div><div class="g2">${t.cols.map(field).join('')}</div></div>`).join('') || '<div class="hint">لا توجد أعمدة يرصدها المعلم في هذه الخطة.</div>'}
          ${refTasks.map(t => { const v = fmtTaskVal(t, day?.vals); return v == null ? '' : `<div class="task-f ref"><b>${esc(t.name)} <span class="hint">للعرض</span></b><span class="small">${t.cols[0].value_type === 'url' ? `<a href="${esc(day.vals[t.cols[0].id])}" target="_blank" rel="noopener">فتح الرابط</a>` : esc(v)}</span></div>`; }).join('')}
        </div>
        ${!reviewOnly && (R.deductions || []).length ? `<div class="card" style="--a:var(--violet);margin-top:12px;padding:8px 12px"><b>الأخطاء</b>
          ${R.deductions.map(d => `<div class="ded"><span>${esc(d.label || 'خطأ')} <span class="hint">(−${d.value})</span></span><span class="ctl"><button type="button" data-d="${esc(d.key)}" data-v="-1" aria-label="إنقاص">−</button><b>${S.ded[d.key] || 0}</b><button type="button" data-d="${esc(d.key)}" data-v="1" aria-label="زيادة">+</button></span></div>`).join('')}
          <div class="row" style="margin-top:6px"><span>الدرجة</span><span class="score">${fmtNum(score, 2)} <span class="hint">من ${R.max}</span></span></div></div>` : ''}`
        : `<div class="hintbox" style="margin-top:10px">${st === 'excused' ? 'يُسجَّل الطالب مستأذنًا لهذا اليوم، ولا يُحسب غيابًا.' : 'يُسجَّل الطالب غائبًا لهذا اليوم، ويدخل في حساب التنبيهات والإنذارات.'}</div>`}
        <label class="f" for="rwNotes" style="margin-top:10px">ملاحظات على الطالب <span class="hint">اختياري</span><textarea id="rwNotes">${esc(S.notes ?? ed?.notes ?? '')}</textarea></label>
        ${ed ? `<label class="f" for="rwReason" style="margin-top:8px">سبب التعديل<input id="rwReason" type="text"></label>` : ''}
        <button class="btn block" id="rwSave" type="button" style="margin-top:12px">${ed ? 'حفظ التعديل' : 'رصد الجلسة'}</button>
      </div>`;
      const keep = () => { S.draft = {}; $$('[data-c]', fa).forEach(i => { S.draft[i.dataset.c] = i.type === 'checkbox' ? i.checked : (i.value === '' ? null : (i.type === 'number' ? Number(i.value) : i.value)); }); S.notes = $('#rwNotes', fa).value; if ($('#rwT', fa)) S.teacherId = $('#rwT', fa).value; };
      $$('[data-st]', fa).forEach(b => b.onclick = () => { keep(); S.status = b.dataset.st; if (S.status === 'makeup' && !S.makeup) { S.makeup = missed[0] || null; S.draft = null; } drawForm(); });
      $('#rwMk', fa) && ($('#rwMk', fa).onchange = e => { S.makeup = e.target.value; S.draft = null; drawForm(); });
      $$('[data-d]', fa).forEach(b => b.onclick = () => { keep(); const k = b.dataset.d; S.ded[k] = Math.max(0, (S.ded[k] || 0) + +b.dataset.v); drawForm(); });
      $('#rwCancelEdit', fa) && ($('#rwCancelEdit', fa).onclick = () => { S.editing = null; S.ded = {}; S.status = 'present'; S.draft = null; S.notes = null; S.makeup = null; drawForm(); });
      $('#rwSave', fa).onclick = () => save(P, day, score);
    }
    async function save(P, day, score) {
      const st = S.status, ed = S.editing, btn = $('#rwSave', fa);
      if ($('#rwT', fa)) S.teacherId = $('#rwT', fa).value;
      if (st === 'makeup' && !S.makeup) return toast('لا يوجد يوم فائت للتعويض عنه', true);
      if (ed && !$('#rwReason', fa).value.trim()) return toast('اكتب سبب التعديل', true);
      const vals = {};
      $$('[data-c]', fa).forEach(i => { const c = P.cols.find(x => x.id === i.dataset.c); if (!c) return; if (c.value_type === 'bool') vals[c.id] = i.checked; else if (i.value !== '') vals[c.id] = c.value_type === 'number' ? Number(i.value) : i.value; });
      for (const c of P.cols.filter(c => c.range_role === 'start' && c.value_type === 'number')) { const e = P.cols.find(x => x.id === c.pair_column_id); if (e && vals[c.id] != null && vals[e.id] != null && vals[c.id] > vals[e.id]) return toast(`«${c.header}» أكبر من «${e.header}»`, true); }
      const mF = P.cols.find(c => c.task === 'memo' && c.range_role === 'start'), mT = P.cols.find(c => c.task === 'memo' && c.range_role === 'end');
      const withScore = ['present', 'makeup'].includes(st);
      const row = {
        student_id: ctx.stu.id, teacher_id: S.teacherId, plan_id: P.id, plan_day_id: day?.id || null,
        rec_date: ed ? ed.rec_date : TODAY, status: st, makes_up_date: st === 'makeup' ? S.makeup : null,
        vals: ['present', 'makeup', 'review_only'].includes(st) ? vals : {}, deductions: withScore ? S.ded : {},
        score: withScore ? score : null, errors_total: withScore ? Object.values(S.ded).reduce((x, y) => x + y, 0) : null,
        memo_from: withScore && mF ? (vals[mF.id] ?? null) : null, memo_to: withScore && mT ? (vals[mT.id] ?? null) : null,
        notes: $('#rwNotes', fa).value.trim() || null, room_id: ctx.roomId || null, created_by: ctx.meId
      };
      btn.disabled = true; btn.textContent = 'جارٍ الحفظ…';
      const { data: ins, error } = await db.from('plan_recitations').insert(row).select('id').single();
      if (error) { btn.disabled = false; btn.textContent = ed ? 'حفظ التعديل' : 'رصد الجلسة'; return toast('لم يُحفظ: ' + error.message, true); }
      if (ed) {
        const { error: e2 } = await db.from('plan_recitations').update({ superseded_by: ins.id, edit_reason: $('#rwReason', fa).value.trim() }).eq('id', ed.id);
        if (e2) toast('حُفظ الرصد الجديد لكن تعذّر ربطه بالقديم: ' + e2.message, true);
      }
      toast(ed ? 'حُفظ التعديل' : 'رُصدت الجلسة');
      S.editing = null; S.ded = {}; S.draft = null; S.notes = null; S.status = 'present'; S.makeup = null;
      await loadHist(); drawForm(); drawHist();
      ctx.onSaved && ctx.onSaved();
    }
    fa.innerHTML = '<div class="loading">جارٍ التحميل…</div>';
    loadHist().then(async () => {
      if (ctx.editId) {
        if (!S.hist.some(r => r.id === ctx.editId)) { const { data } = await db.from('plan_recitations').select('*').eq('id', ctx.editId).maybeSingle(); if (data) S.hist.push(data); }
        drawHist(); startEdit(ctx.editId); return;
      }
      drawForm(); drawHist();
    });
    return { reload: async () => { await loadHist(); drawForm(); drawHist(); } };
  }
  // تحميل خطط بأعمدتها وأيامها
  async function loadPlansFull(planIds) {
    const PLANS = {};
    if (!planIds.length) return PLANS;
    const [p, c, d] = await Promise.all([
      db.from('program_plans').select('*').in('id', planIds),
      db.from('plan_columns').select('*').in('plan_id', planIds).order('seq'),
      fetchAll(() => db.from('plan_days').select('id, plan_id, day_number, vals').in('plan_id', planIds))
    ]);
    (p.data || []).forEach(x => PLANS[x.id] = { ...x, cols: [], days: {} });
    (c.data || []).forEach(x => PLANS[x.plan_id]?.cols.push(x));
    d.forEach(x => { if (PLANS[x.plan_id]) PLANS[x.plan_id].days[x.day_number] = x; });
    return PLANS;
  }

  // ===== التثبيت على الجوال وإشعارات الجوال =====
  const VAPID_PUBLIC = 'BGOb1JtomPyxrCk3SiqluCzs97TDuGXRXnScFMYgIrpGYAEhT1NbFUPNhDk01h2VZw3DSvwAXbQ405jF7Z-aNws';
  const ua = navigator.userAgent || '';
  const isIOS = /iPhone|iPad|iPod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isAndroid = /Android/i.test(ua);
  const isMobile = isIOS || isAndroid;
  const isStandalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const pushSupported = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  let deferredPrompt = null;
  window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); deferredPrompt = e; document.dispatchEvent(new Event('sonnan-installable')); });
  window.addEventListener('appinstalled', () => { deferredPrompt = null; closeSheet(); toast('ثُبّت التطبيق على جهازك'); });
  const ls = { get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} } };
  const snoozed = k => { const t = +ls.get(k) || 0; return Date.now() - t < 3 * 864e5; };
  const b64ToU8 = s => { const p = '='.repeat((4 - s.length % 4) % 4); const raw = atob((s + p).replace(/-/g, '+').replace(/_/g, '/')); return Uint8Array.from([...raw].map(c => c.charCodeAt(0))); };
  async function registerSW() { if (!('serviceWorker' in navigator)) return null; try { return await navigator.serviceWorker.register('sw.js'); } catch (e) { return null; } }

  function closeSheet() { $('#pwaSheet')?.remove(); $('#pwaBack')?.remove(); }
  function sheet(html, onMount) {
    closeSheet();
    const back = document.createElement('div'); back.id = 'pwaBack'; back.className = 'drawer-back';
    const s = document.createElement('div'); s.id = 'pwaSheet'; s.className = 'pwa-sheet'; s.setAttribute('role', 'dialog');
    s.innerHTML = `<div class="pwa-grip"></div>${html}`;
    document.body.append(back, s);
    back.onclick = closeSheet;
    onMount && onMount(s);
  }
  const shareIcon = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="vertical-align:-4px"><path d="M12 3v12M8 7l4-4 4 4"/><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/></svg>';
  const addIcon = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true" style="vertical-align:-4px"><rect x="4" y="4" width="16" height="16" rx="4"/><path d="M12 8v8M8 12h8"/></svg>';
  function installSheet() {
    const head = `<div class="pwa-head"><img src="icons/icon-192.png" alt="" width="56" height="56"><div><b>ثبّت تطبيق سنن على جوالك</b><p>يفتح بضغطة من الشاشة الرئيسية، وتصلك عليه الإشعارات.</p></div></div>`;
    if (isIOS) {
      sheet(`${head}<ol class="pwa-steps"><li>اضغط زر المشاركة ${shareIcon} أسفل المتصفح (في سفاري).</li><li>اختر «إضافة إلى الشاشة الرئيسية» ${addIcon}</li><li>اضغط «إضافة»، ثم افتح سنن من الشاشة الرئيسية وسجّل دخولك.</li></ol>
        <p class="hint">على الآيفون لا تعمل الإشعارات إلا بعد التثبيت بهذه الطريقة.</p><button class="btn ghost block" id="pwaLater">لاحقًا</button>`, s => { $('#pwaLater', s).onclick = () => { ls.set('sonnan-install-snooze', Date.now()); closeSheet(); }; });
    } else if (deferredPrompt) {
      sheet(`${head}<button class="btn block" id="pwaGo">تثبيت التطبيق</button><button class="btn ghost block" id="pwaLater" style="margin-top:8px">لاحقًا</button>`, s => {
        $('#pwaGo', s).onclick = async () => { const p = deferredPrompt; deferredPrompt = null; p.prompt(); const r = await p.userChoice; closeSheet(); if (r.outcome !== 'accepted') ls.set('sonnan-install-snooze', Date.now()); };
        $('#pwaLater', s).onclick = () => { ls.set('sonnan-install-snooze', Date.now()); closeSheet(); };
      });
    } else {
      sheet(`${head}<ol class="pwa-steps"><li>افتح قائمة المتصفح (⋮) أعلى الشاشة.</li><li>اختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية».</li></ol><button class="btn ghost block" id="pwaLater">لاحقًا</button>`, s => { $('#pwaLater', s).onclick = () => { ls.set('sonnan-install-snooze', Date.now()); closeSheet(); }; });
    }
  }
  // يحفظ اشتراك هذا الجهاز للمستخدم الحالي
  async function saveSubscription(reg) {
    let sub = await reg.pushManager.getSubscription();
    if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64ToU8(VAPID_PUBLIC) });
    const j = sub.toJSON();
    const { data: { user } } = await db.auth.getUser();
    const { data: me } = await db.from('users').select('id').eq('id', user.id).maybeSingle();
    await db.from('push_subscriptions').delete().eq('endpoint', j.endpoint);
    const { error } = await db.from('push_subscriptions').insert({ user_id: me.id, endpoint: j.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth, user_agent: ua.slice(0, 250) });
    // 23505: الجهاز نفسه مسجل لحساب آخر سجّل الدخول عليه سابقًا
    if (error && error.code !== '23505') throw error;
  }
  async function enablePush() {
    const reg = await registerSW();
    if (!reg || !pushSupported()) throw new Error('هذا المتصفح لا يدعم الإشعارات');
    const perm = await Notification.requestPermission();
    if (perm !== 'granted') throw new Error(perm === 'denied' ? 'رُفض الإذن. فعّل الإشعارات لسنن من إعدادات الجوال' : 'لم يُمنح الإذن');
    await navigator.serviceWorker.ready;
    await saveSubscription(reg);
  }
  function pushSheet() {
    sheet(`<div class="pwa-head"><div class="pwa-bell">${ICON.bell}</div><div><b>فعّل الإشعارات</b><p>تصلك رسائل المعلم والإدارة، وقرارات الاستئذان، والتنبيهات، حتى والتطبيق مغلق.</p></div></div>
      <button class="btn block" id="pushGo">تفعيل الإشعارات</button><button class="btn ghost block" id="pushLater" style="margin-top:8px">لاحقًا</button>`, s => {
      $('#pushGo', s).onclick = async () => { const b = $('#pushGo', s); b.disabled = true; try { await enablePush(); closeSheet(); toast('فُعّلت الإشعارات على هذا الجهاز'); document.dispatchEvent(new Event('sonnan-push')); } catch (e) { b.disabled = false; toast(e.message, true); } };
      $('#pushLater', s).onclick = () => { ls.set('sonnan-push-snooze', Date.now()); closeSheet(); };
    });
  }
  const pushState = () => !pushSupported() ? (isIOS && !isStandalone() ? 'needs-install' : 'unsupported') : Notification.permission;
  // يُستدعى عند فتح صفحة الطالب أو المعلم
  async function setupPWA({ ask = true } = {}) {
    const reg = await registerSW();
    // جهاز سبق أن سمح بالإشعارات: نتأكد أن اشتراكه محفوظ
    if (reg && pushSupported() && Notification.permission === 'granted') { try { await saveSubscription(reg); } catch (e) {} }
    if (!ask || !isMobile) return;
    if (!isStandalone() && !snoozed('sonnan-install-snooze')) {
      if (isAndroid && !deferredPrompt) {
        // ننتظر قليلًا حتى يعلن المتصفح أن التطبيق قابل للتثبيت
        const t = setTimeout(installSheet, 2500);
        document.addEventListener('sonnan-installable', () => { clearTimeout(t); installSheet(); }, { once: true });
      } else installSheet();
      return;
    }
    if (pushSupported() && Notification.permission === 'default' && !snoozed('sonnan-push-snooze')) pushSheet();
  }

  // حقول الجنسية: قائمة اقتراحات بالأسماء الموحدة (قاعدة البيانات توحّد أي صيغة عند الحفظ أيضًا)
  let natLoaded = false;
  document.addEventListener('focusin', async e => {
    const el = e.target;
    if (!(el instanceof HTMLInputElement) || !/^(pf|sf|tf)Nat$/.test(el.id)) return;
    el.setAttribute('list', 'natList'); el.autocomplete = 'off';
    if (natLoaded) return; natLoaded = true;
    const { data } = await db.from('nationality_names').select('canonical');
    const dl = document.createElement('datalist'); dl.id = 'natList';
    [...new Set((data || []).map(x => x.canonical))].sort((a, b) => a.localeCompare(b, 'ar')).forEach(v => { const o = document.createElement('option'); o.value = v; dl.appendChild(o); });
    document.body.appendChild(dl);
  });

  window.App = { exportXlsx, recordWidget, loadPlansFull, setupPWA, installSheet, pushSheet, enablePush, pushState, isIOS, isAndroid, isMobile, isStandalone, donut, tally, PALETTE, topIcons, refreshBell, openInbox, profileSection, ICON, db, $, $$, esc, norm, fmtNum, todayMakkah, nowMakkahHM, dowMakkah, addDays, daysBetween, hijri, greg, dayName, DAYS, workdaysBetween,
    STATUS, statusPill, STU_STATUS, toast, fetchAll, requireRole, homeOf, logout, dataTable, fullscreenBtn, drawer, closeDrawer, confirmBox,
    unionCount, planDayFor, isRecitationDay, TASKS, taskName, groupTasks, fmtTaskVal, taskAmount, svg };
})();
