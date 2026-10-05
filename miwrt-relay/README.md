# MiWRT notification relay

A Cloudflare Worker that passes router alerts to Apple's push service.

Apple only delivers a notification signed with the key of the app's publisher. That key cannot be put into firmware, so a router without its own key hands its notifications to this relay.

## What it sees

- each phone's notification address (a random value Apple issues per app install);
- the kind of alert (`radio`, `internet`, `dns`, `device`, `router`) and its severity;
- an encrypted blob.

The alert's title and text are encrypted on the router (AES-256-CBC, then HMAC-SHA256) with a key the phone made and gave to the router at registration, over the pinned HTTPS connection. The relay and Apple cannot read them; the phone's notification extension decrypts them. The visible fallback text is a fixed "Your router has an alert".

Nothing is stored and nothing is logged.

## Limits

30 requests a minute per sending address, 10 notifications a minute per phone, 20 phones per request, 16 kB per request. Only the app's own bundle ID is accepted as topic.

## Protocol

`GET /health` → `{ ok, service, version, ready }`

`POST /v1/push`

```json
{ "app": "cloud.iroham.miwrt", "kind": "device", "severity": "warning", "id": "…",
  "messages": [ { "token": "<hex>", "env": "production", "enc": "<base64>" } ] }
```

Answer: `{ "delivered": 1, "gone": ["<token Apple no longer accepts>"] }`.

## Running your own

```
npx wrangler deploy
npx wrangler secret put APNS_KEY       # contents of AuthKey_XXXXXXXXXX.p8
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
```

A relay only works for app builds signed by the owner of that key. Point a router at it with `POST /v1/settings` `{ "push": { "relay": "https://…" } }`.
