// يرسل إشعارات الجوال المنتظرة (قناة push) لكل أجهزة المستلم، ولا يرسل الإشعار مرتين
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  // مفاتيح VAPID في جدول app_secrets الذي لا يقرؤه إلا مفتاح الخدمة
  const { data: sec } = await sb.from('app_secrets').select('key, value').in('key', ['vapid_public', 'vapid_private', 'vapid_subject']);
  const S = Object.fromEntries((sec || []).map((x) => [x.key, x.value]));
  if (!S.vapid_public || !S.vapid_private) return json({ error: 'missing vapid keys' }, 500);
  webpush.setVapidDetails(S.vapid_subject || 'https://sonnan-web.github.io/sonnan/', S.vapid_public, S.vapid_private);

  const { data: queue, error } = await sb.from('notifications').select('id, recipient_user_id, title, body, link').eq('channel', 'push').eq('status', 'queued').order('created_at').limit(300);
  if (error) return json({ error: error.message }, 500);
  const out = { sent: 0, skipped: 0, failed: 0 };
  const subsCache: Record<string, { id: string; endpoint: string; p256dh: string; auth: string }[]> = {};
  for (const n of queue || []) {
    // حجز الإشعار بتغيير حالته أولًا حتى لا يُرسل مرتين إن عملت نسختان معًا
    const { data: claimed } = await sb.from('notifications').update({ status: 'sent', sent_at: new Date().toISOString() }).eq('id', n.id).eq('status', 'queued').select('id');
    if (!claimed?.length) continue;
    if (!subsCache[n.recipient_user_id]) {
      const { data: subs } = await sb.from('push_subscriptions').select('id, endpoint, p256dh, auth').eq('user_id', n.recipient_user_id);
      subsCache[n.recipient_user_id] = subs || [];
    }
    const subs = subsCache[n.recipient_user_id];
    if (!subs.length) { await sb.from('notifications').update({ status: 'skipped', error: 'لا يوجد جهاز مفعّل للإشعارات' }).eq('id', n.id); out.skipped++; continue; }
    const payload = JSON.stringify({ title: n.title, body: n.body, url: n.link || null, tag: n.id });
    let ok = 0; const errs: string[] = [];
    for (const s of subs) {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400, urgency: 'high' });
        ok++;
        await sb.from('push_subscriptions').update({ last_ok_at: new Date().toISOString(), fail_count: 0 }).eq('id', s.id);
      } catch (e) {
        const code = (e as { statusCode?: number })?.statusCode;
        errs.push(String(code || (e as Error).message).slice(0, 120));
        // الاشتراك المنتهي (404/410) يُحذف
        if (code === 404 || code === 410) await sb.from('push_subscriptions').delete().eq('id', s.id);
      }
    }
    if (ok) out.sent++;
    else { await sb.from('notifications').update({ status: 'failed', error: errs.join('; ') }).eq('id', n.id); out.failed++; }
  }
  return json(out);
});
