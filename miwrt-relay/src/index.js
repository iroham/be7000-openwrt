// MiWRT notification relay (Cloudflare Worker).
//
// Apple only delivers a notification signed with the app publisher's key. A router cannot hold that key
// (firmware is public), so routers hand their notifications to this relay and the relay passes them to Apple.
//
// What the relay sees: each phone's notification address and an encrypted blob. The alert's text is encrypted
// on the router with a key only the phone has; the relay and Apple cannot read it. Nothing is logged.
//
// What the relay keeps (KV namespace BINDINGS): for each phone, a fingerprint (SHA-256) of its notification
// address next to a fingerprint of a random value that the phone made and gave to its router. Notifications
// for that phone are then only accepted with that value, so knowing a phone's address is not enough to send
// to it. A record goes away 60 days after it was last used. Neither fingerprint can be turned back.
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

// A limiter that is missing or failing counts as "over the limit": the relay sends nothing it cannot count.
async function limited(limiter, key) {
  if (!limiter) return true;
  try { return !(await limiter.limit({ key })).success; } catch (e) { return true; }
}

// One home is one sender. An IPv6 home has a whole /64 of addresses, so only the network part counts.
function senderKey(ip) {
  if (!ip.includes(':')) return ip;
  const [head, tail = ''] = ip.toLowerCase().split('::');
  const h = head ? head.split(':') : [], t = tail ? tail.split(':') : [];
  const full = ip.includes('::') ? [...h, ...Array(Math.max(0, 8 - h.length - t.length)).fill('0'), ...t] : h;
  return full.slice(0, 4).map((x) => x.replace(/^0+(?=.)/, '')).join(':') + '::/64';
}

const sha256hex = async (text) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)))].map((b) => b.toString(16).padStart(2, '0')).join('');

// Does this message come from the router the phone registered with? A phone whose app is too old to have
// made the value has no record and is served as before; the first message that carries one makes the record.
async function bound(env, m) {
  if (!env.BINDINGS) return true;
  const day = String(Math.floor(Date.now() / 86400000));
  const phone = await sha256hex('phone|' + m.token);
  const mine = typeof m.auth === 'string' && /^[0-9a-f]{64}$/.test(m.auth) ? await sha256hex('sender|' + m.auth) : null;
  const kept = await env.BINDINGS.get(phone);
  if (!kept) {
    if (mine) await env.BINDINGS.put(phone, mine + ':' + day, { expirationTtl: 5184000 });
    return true;
  }
  const [who, when] = kept.split(':');
  if (who !== mine) return false;
  if (when !== day) await env.BINDINGS.put(phone, mine + ':' + day, { expirationTtl: 5184000 });   // at most one write a day
  return true;
}

async function deliver(env, m, meta) {
  const kind = String(meta.kind || 'router').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 32) || 'router';
  const id = typeof meta.id === 'string' && /^[A-Za-z0-9_-]{1,40}$/.test(meta.id) ? meta.id : undefined;
  const payload = { aps: { alert: GENERIC, sound: 'default', 'thread-id': kind }, kind, alert_id: id };
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
    if (request.method === 'GET' && url.pathname === '/health') return json(200, { ok: true, service: 'miwrt-relay', version: 3, ready: ready(env) });
    if (request.method !== 'POST' || url.pathname !== '/v1/push') return json(404, { error: 'not found' });

    const sender = senderKey(request.headers.get('cf-connecting-ip') || 'unknown');
    // the size is checked before the body is read
    const declared = Number(request.headers.get('content-length'));
    if (!Number.isFinite(declared) || declared <= 0 || declared > MAX_BODY) return json(declared > MAX_BODY ? 413 : 411, { error: declared > MAX_BODY ? 'too large' : 'length required' });
    const text = await request.text();
    if (text.length > MAX_BODY) return json(413, { error: 'too large' });
    let b;
    try { b = JSON.parse(text); } catch (e) { return json(400, { error: 'bad request' }); }
    if (!b || typeof b !== 'object' || !Array.isArray(b.messages)) return json(400, { error: 'bad request' });
    if (b.app !== (env.BUNDLE_ID || 'cloud.iroham.miwrt')) return json(400, { error: 'unknown app' });
    if (!ready(env)) return json(503, { error: 'The relay has no Apple push key yet.' });

    let delivered = 0, refused = false, broken = false, counted = 0, blocked = 0;
    const gone = [];
    for (const m of b.messages.slice(0, MAX_MESSAGES)) {
      if (!m || typeof m.token !== 'string' || !/^[0-9a-f]{64,200}$/.test(m.token) || typeof m.env !== 'string' || !Object.hasOwn(HOSTS, m.env)) continue;
      if (m.enc !== undefined && (typeof m.enc !== 'string' || !/^[A-Za-z0-9+/=]{44,3000}$/.test(m.enc))) continue;
      // every notification counts against the sender, not every request
      if (await limited(env.PER_SENDER, sender)) {
        if (!counted) return json(429, { error: 'Too many notifications from this address. Try again in a minute.' });
        break;
      }
      counted++;
      try { if (!(await bound(env, m))) { blocked++; continue; } } catch (e) { broken = true; continue; }
      if (await limited(env.PER_PHONE, m.token)) continue;
      try {
        const status = await deliver(env, m, { kind: b.kind, severity: b.severity, id: b.id });
        if (status === 200) delivered++;
        if (status === 410) gone.push(m.token);
        if (status === 403) refused = true;   // Apple did not accept the relay's own key
      } catch (e) { broken = true; /* one failed phone must not stop the others */ }
    }
    if (broken && !delivered) return json(502, { error: 'The relay could not sign or send the notification.', delivered, gone });
    return json(refused ? 502 : 200, refused ? { error: 'Apple refused the relay\'s push key.', delivered, gone } : { delivered, gone, blocked });
  },
};
