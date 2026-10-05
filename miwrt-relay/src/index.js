// MiWRT notification relay (Cloudflare Worker).
//
// Apple only delivers a notification signed with the app publisher's key. A router cannot hold that key
// (firmware is public), so routers hand their notifications to this relay and the relay passes them to Apple.
//
// What the relay sees: each phone's notification address and an encrypted blob. The alert's text is encrypted
// on the router with a key only the phone has; the relay and Apple cannot read it. Nothing is stored or logged.
//
// Secrets (wrangler secret put): APNS_KEY (contents of AuthKey_XXXXXXXXXX.p8), APNS_KEY_ID, APNS_TEAM_ID.
// Optional variable: BUNDLE_ID (default cloud.iroham.miwrt).

const HOSTS = { production: 'https://api.push.apple.com', sandbox: 'https://api.sandbox.push.apple.com' };
const GENERIC = { title: 'MiWRT', body: 'Your router has an alert. Open MiWRT to read it.' };
const MAX_BODY = 16384, MAX_MESSAGES = 20;

let cached = { token: null, made: 0 };

const b64url = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const json = (status, obj) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
const ready = (env) => !!(env.APNS_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID);

// The signed token that proves to Apple who is sending. Apple wants it reused: kept for 50 minutes.
async function providerToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cached.token && now - cached.made < 3000) return cached.token;
  const der = Uint8Array.from(atob(env.APNS_KEY.replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const enc = new TextEncoder();
  const signing = b64url(enc.encode(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID }))) + '.' + b64url(enc.encode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now })));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(signing));
  cached = { token: signing + '.' + b64url(sig), made: now };
  return cached.token;
}

async function limited(limiter, key) {
  if (!limiter) return false;
  try { return !(await limiter.limit({ key })).success; } catch (e) { return false; }
}

async function deliver(env, m, meta) {
  const kind = String(meta.kind || 'router').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 32) || 'router';
  const payload = { aps: { alert: GENERIC, sound: 'default', 'thread-id': kind }, kind, alert_id: meta.id };
  if (m.enc) { payload.aps['mutable-content'] = 1; payload.enc = m.enc; }
  const r = await fetch(`${HOSTS[m.env]}/3/device/${m.token}`, {
    method: 'POST',
    headers: {
      authorization: 'bearer ' + (await providerToken(env)),
      'apns-topic': env.BUNDLE_ID || 'cloud.iroham.miwrt',
      'apns-push-type': 'alert',
      'apns-priority': meta.severity === 'critical' ? '10' : '5',
      'apns-collapse-id': kind,
      'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600),
    },
    body: JSON.stringify(payload),
  });
  if (r.status === 403) cached = { token: null, made: 0 };
  return r.status;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/health') return json(200, { ok: true, service: 'miwrt-relay', version: 2, ready: ready(env) });
    if (request.method !== 'POST' || url.pathname !== '/v1/push') return json(404, { error: 'not found' });

    const ip = request.headers.get('cf-connecting-ip') || 'unknown';
    if (await limited(env.PER_SENDER, ip)) return json(429, { error: 'Too many notifications from this address. Try again in a minute.' });

    const text = await request.text();
    if (text.length > MAX_BODY) return json(413, { error: 'too large' });
    let b;
    try { b = JSON.parse(text); } catch (e) { return json(400, { error: 'bad request' }); }
    if (!b || typeof b !== 'object' || !Array.isArray(b.messages)) return json(400, { error: 'bad request' });
    if (b.app !== (env.BUNDLE_ID || 'cloud.iroham.miwrt')) return json(400, { error: 'unknown app' });
    if (!ready(env)) return json(503, { error: 'The relay has no Apple push key yet.' });

    let delivered = 0;
    const gone = [];
    for (const m of b.messages.slice(0, MAX_MESSAGES)) {
      if (!m || typeof m.token !== 'string' || !/^[0-9a-f]{64,200}$/.test(m.token) || !HOSTS[m.env]) continue;
      if (m.enc !== undefined && (typeof m.enc !== 'string' || !/^[A-Za-z0-9+/=]{44,3000}$/.test(m.enc))) continue;
      if (await limited(env.PER_PHONE, m.token)) continue;
      try {
        const status = await deliver(env, m, { kind: b.kind, severity: b.severity, id: b.id });
        if (status === 200) delivered++;
        if (status === 410) gone.push(m.token);
      } catch (e) { /* one failed phone must not stop the others */ }
    }
    return json(200, { delivered, gone });
  },
};
