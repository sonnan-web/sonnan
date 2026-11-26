/* عامل الخدمة لمنصة سنن: يجعل المنصة قابلة للتثبيت، ويستقبل إشعارات الجوال */
const VERSION = 'sonnan-v1';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

// الصفحات تُطلب من الشبكة دائمًا (البيانات حيّة)، ولا تُخزَّن بيانات الطلاب في الجهاز
self.addEventListener('fetch', e => {
  if (e.request.mode === 'navigate') {
    e.respondWith(fetch(e.request).catch(() => new Response(
      '<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><body style="font-family:Tahoma;background:#0F2F33;color:#fff;display:grid;place-items:center;min-height:100vh;margin:0;text-align:center"><div><h2 style="color:#CBB994">لا يوجد اتصال بالإنترنت</h2><p>تحقق من الاتصال ثم أعد المحاولة.</p></div></body></html>',
      { headers: { 'Content-Type': 'text/html; charset=utf-8' } })));
  }
});

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = { body: e.data ? e.data.text() : '' }; }
  const title = d.title || 'منصة سنن';
  e.waitUntil(self.registration.showNotification(title, {
    body: d.body || '',
    icon: 'icons/icon-192.png',
    badge: 'icons/badge-96.png',
    dir: 'rtl', lang: 'ar',
    tag: d.tag || undefined,
    data: { url: d.url || 'index.html' }
  }));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL(e.notification.data?.url || 'index.html', self.registration.scope).href;
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of all) { if (c.url.startsWith(self.registration.scope)) { await c.focus(); if ('navigate' in c) c.navigate(url); return; } }
    await self.clients.openWindow(url);
  })());
});
