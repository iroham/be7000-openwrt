// MiWRT hub, second part: Wi-Fi settings, guest Wi-Fi, firmware, blocked threats, connection test, summaries.
'use strict';

import { readfile, writefile, stat, unlink } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';
import * as hub from 'miwrt.hub';

const ETC = '/etc/miwrt';
const RUN = '/tmp/miwrt';
const BANDS = { '2g': '2.4 GHz', '5g': '5 GHz', '6g': '6 GHz' };
const NET_LABEL = { lan: 'Main', iot: 'IoT', guest: 'Guest' };

function valid_ssid(s) {
	return type(s) == 'string' && length(s) >= 1 && length(s) <= 32 && !match(s, /[[:cntrl:]]/);
}

function valid_key(k) {
	return type(k) == 'string' && length(k) >= 8 && length(k) <= 63 && match(k, /^[ -~]+$/) != null;
}

function sid_ok(c, sid) {
	return type(sid) == 'string' && match(sid, /^[A-Za-z0-9_]{1,40}$/) && c.get('wireless', sid) == 'wifi-iface';
}

// ---------- Wi-Fi ----------

export function wifi_list() {
	let c = cursor(), conn = connect(), radios = [], nets = [];
	let live = {};
	for (let rname, r in (conn.call('network.wireless', 'status') ?? {}))
		for (let i in (r.interfaces ?? []))
			if (i.section) live[i.section] = { ifname: i.ifname, up: !!r.up };
	c.foreach('wireless', 'wifi-device', r => {
		push(radios, { id: r['.name'], band: BANDS[r.band] ?? r.band, channel: r.channel, width: r.htmode, country: r.country, enabled: r.disabled != '1' });
	});
	c.foreach('wireless', 'wifi-iface', w => {
		if (w.mode != 'ap') return;
		let radio = filter(radios, r => r.id == w.device)[0] ?? {};
		let clients = 0, l = live[w['.name']];
		if (l?.ifname) clients = length(conn.call('iwinfo', 'assoclist', { device: l.ifname })?.results ?? []);
		push(nets, { id: w['.name'], ssid: w.ssid, band: radio.band, network: NET_LABEL[w.network] ?? w.network, guest: w.network == 'guest',
			enabled: w.disabled != '1' && radio.enabled !== false, hidden: w.hidden == '1',
			security: w.encryption == 'none' ? 'Open' : (match(w.encryption ?? '', /sae/) ? (match(w.encryption, /mixed/) ? 'WPA2 / WPA3' : 'WPA3') : 'WPA2'),
			clients });
	});
	return { networks: nets, radios };
};

/* Name and password of one Wi-Fi network, for the QR code. Asked for only when the user opens it. */
export function wifi_secret(sid) {
	let c = cursor();
	if (!sid_ok(c, sid)) return { error: 'That Wi-Fi network no longer exists.' };
	let enc = c.get('wireless', sid, 'encryption') ?? 'none';
	return { ssid: c.get('wireless', sid, 'ssid'), key: enc == 'none' ? '' : (c.get('wireless', sid, 'key') ?? ''), open: enc == 'none', hidden: c.get('wireless', sid, 'hidden') == '1' };
};

function reload_wifi_soon() {
	// answer the app first, then restart the radios
	system('(sleep 2; wifi reload) >/dev/null 2>&1 &');
}

export function wifi_update(sid, b) {
	return hub.locked(() => {
		let c = cursor();
		if (!sid_ok(c, sid)) return 'That Wi-Fi network no longer exists.';
		let changed = false;
		if ('ssid' in b) {
			if (!valid_ssid(b.ssid)) return 'A Wi-Fi name needs 1 to 32 characters.';
			if (b.ssid != c.get('wireless', sid, 'ssid')) { c.set('wireless', sid, 'ssid', b.ssid); changed = true; }
		}
		if ('key' in b) {
			if (!valid_key(b.key)) return 'A Wi-Fi password needs 8 to 63 characters (letters, digits and common symbols).';
			if ((c.get('wireless', sid, 'encryption') ?? 'none') == 'none') return 'This network is open. Set its security on the router\'s web page first.';
			if (b.key != c.get('wireless', sid, 'key')) { c.set('wireless', sid, 'key', b.key); changed = true; }
		}
		if ('enabled' in b) {
			let want = b.enabled ? '0' : '1';
			if (want != (c.get('wireless', sid, 'disabled') ?? '0')) { c.set('wireless', sid, 'disabled', want); changed = true; }
		}
		if (!changed) return null;
		writefile(ETC + '/wireless.prev', readfile('/etc/config/wireless') ?? '');   // one step back, by hand: cp /etc/miwrt/wireless.prev /etc/config/wireless; wifi reload
		system([ 'chmod', '600', ETC + '/wireless.prev' ]);
		c.commit('wireless');
		hub.add_alert('router', 'Wi-Fi settings changed', `${c.get('wireless', sid, 'ssid')}: from the app.`, 'info');
		reload_wifi_soon();
		return null;
	});
};

// ---------- guest Wi-Fi ----------

function random_key() {
	// 12 characters without look-alikes
	let abc = 'abcdefghjkmnpqrstuvwxyz23456789', raw = hexenc(hub.random_bytes(12)), out = '';
	for (let i = 0; i < 12; i++) out += substr(abc, int(substr(raw, i * 2, 2), 16) % length(abc), 1);
	return out;
}

function guest_subnet(conn) {
	let used = {};
	for (let i in (conn.call('network.interface', 'dump')?.interface ?? []))
		for (let a in (i['ipv4-address'] ?? [])) used[join('.', slice(split(a.address, '.'), 0, 3))] = true;
	for (let n = 50; n < 60; n++) if (!used[`192.168.${n}`]) return `192.168.${n}`;
	return null;
}

export function guest_status() {
	let c = cursor(), ifaces = [], s = hub.settings();
	c.foreach('wireless', 'wifi-iface', w => { if (w.network == 'guest' && match(w['.name'], /^miwrt_guest_/)) push(ifaces, w); });
	if (!length(ifaces)) return { exists: false, enabled: false };
	return { exists: true, enabled: length(filter(ifaces, w => w.disabled != '1')) > 0, ssid: ifaces[0].ssid, key: ifaces[0].key,
		until: s.guest_until > time() ? s.guest_until : null };
};

/* Creates the guest network the first time: its own bridge, addresses and firewall zone.
   Guests reach the internet and nothing in the house, and cannot see each other. */
function guest_create(c, conn, ssid, key) {
	let net = guest_subnet(conn);
	if (!net) return 'No free address range for a guest network.';
	c.set('network', 'miwrt_br_guest', 'device');
	c.set('network', 'miwrt_br_guest', 'name', 'br-guest');
	c.set('network', 'miwrt_br_guest', 'type', 'bridge');
	c.set('network', 'miwrt_br_guest', 'bridge_empty', '1');
	c.set('network', 'guest', 'interface');
	c.set('network', 'guest', 'proto', 'static');
	c.set('network', 'guest', 'device', 'br-guest');
	c.set('network', 'guest', 'ipaddr', net + '.1/24');

	c.set('dhcp', 'guest', 'dhcp');
	c.set('dhcp', 'guest', 'interface', 'guest');
	c.set('dhcp', 'guest', 'start', '10');
	c.set('dhcp', 'guest', 'limit', '200');
	c.set('dhcp', 'guest', 'leasetime', '2h');
	c.set('dhcp', 'guest', 'dhcpv4', 'server');

	c.set('firewall', 'miwrt_guest', 'zone');
	c.set('firewall', 'miwrt_guest', 'name', 'guest');
	c.set('firewall', 'miwrt_guest', 'network', [ 'guest' ]);
	c.set('firewall', 'miwrt_guest', 'input', 'REJECT');
	c.set('firewall', 'miwrt_guest', 'output', 'ACCEPT');
	c.set('firewall', 'miwrt_guest', 'forward', 'REJECT');
	c.set('firewall', 'miwrt_guest_wan', 'forwarding');
	c.set('firewall', 'miwrt_guest_wan', 'src', 'guest');
	c.set('firewall', 'miwrt_guest_wan', 'dest', 'wan');
	for (let r in [ [ 'dhcp', 'udp', '67' ], [ 'dns', 'tcp udp', '53' ] ]) {
		let sid = 'miwrt_guest_' + r[0];
		c.set('firewall', sid, 'rule');
		c.set('firewall', sid, 'name', 'Guest: ' + uc(r[0]));
		c.set('firewall', sid, 'src', 'guest');
		c.set('firewall', sid, 'proto', r[1]);
		c.set('firewall', sid, 'dest_port', r[2]);
		c.set('firewall', sid, 'target', 'ACCEPT');
	}

	let n = 0;
	c.foreach('wireless', 'wifi-device', r => {
		let sid = 'miwrt_guest_' + r['.name'];
		if (!match(sid, /^[A-Za-z0-9_]+$/)) return;
		c.set('wireless', sid, 'wifi-iface');
		c.set('wireless', sid, 'device', r['.name']);
		c.set('wireless', sid, 'mode', 'ap');
		c.set('wireless', sid, 'network', 'guest');
		c.set('wireless', sid, 'ssid', ssid);
		c.set('wireless', sid, 'encryption', 'psk2');
		c.set('wireless', sid, 'key', key);
		c.set('wireless', sid, 'isolate', '1');
		c.set('wireless', sid, 'disabled', '1');
		n++;
	});
	if (!n) return 'This router has no Wi-Fi radio to put a guest network on.';
	return null;
}

export function guest_set(b) {
	return hub.locked(() => {
		let c = cursor(), conn = connect(), st = guest_status();
		let ssid = ('ssid' in b) ? b.ssid : (st.ssid ?? 'Guest Wi-Fi');
		let key = ('key' in b && length(b.key ?? '')) ? b.key : (st.key ?? random_key());
		if (!valid_ssid(ssid)) return 'A Wi-Fi name needs 1 to 32 characters.';
		if (!valid_key(key)) return 'A Wi-Fi password needs 8 to 63 characters.';
		let hours = int(+(b.hours ?? 0));
		if (hours < 0 || hours > 168) return 'Choose up to 7 days.';

		if (!st.exists) {
			if (!b.on) return null;
			let err = guest_create(c, conn, ssid, key);
			if (!err) {
				c.save('network'); c.save('dhcp'); c.save('firewall');
				if (system([ 'fw4', 'check' ]) != 0) err = 'The router refused the guest firewall rules.';
			}
			if (err) {
				for (let cfg in [ 'network', 'dhcp', 'firewall', 'wireless' ]) c.revert(cfg);
				return err;
			}
		}
		c.foreach('wireless', 'wifi-iface', w => {
			if (w.network != 'guest' || !match(w['.name'], /^miwrt_guest_/)) return;
			c.set('wireless', w['.name'], 'ssid', ssid);
			c.set('wireless', w['.name'], 'key', key);
			c.set('wireless', w['.name'], 'disabled', b.on ? '0' : '1');
		});
		for (let cfg in [ 'network', 'dhcp', 'firewall', 'wireless' ]) c.commit(cfg);

		let s = hub.load(ETC + '/settings.json', {});
		s.guest_until = (b.on && hours > 0) ? time() + hours * 3600 : 0;
		hub.save(ETC + '/settings.json', s);
		hub.add_alert('router', b.on ? 'Guest Wi-Fi turned on' : 'Guest Wi-Fi turned off', b.on ? (hours > 0 ? `${ssid}, for ${hours} h.` : ssid) : '', 'info');
		// new network pieces first, then the radios
		system('(sleep 2; /etc/init.d/network reload; sleep 3; /etc/init.d/firewall reload; /etc/init.d/dnsmasq reload) >/dev/null 2>&1 &');
		return null;
	});
};

/* Called on every pass: switches guest Wi-Fi off when its timer ran out. */
export function guest_expire() {
	let s = hub.settings();
	if (s.guest_until > 0 && s.guest_until <= time()) guest_set({ on: false });
};

// ---------- firmware ----------

export function firmware(check) {
	let out = {};
	try { out = json(hub.run(`be7000-update ${check ? 'check' : 'status'} --json 2>/dev/null`)); } catch (e) {}
	let board = connect().call('system', 'board') ?? {};
	let cur = out.installed?.version ?? board.release?.version, latest = out.latest?.latest;
	return { current: cur, description: board.release?.description, built: out.installed?.date,
		latest, latest_name: out.latest?.name, published: out.latest?.published_at, notes: substr(out.latest?.body ?? '', 0, 4000),
		checked_at: +(out.latest?.checked_at ?? 0), update_available: !!(latest && cur && latest != cur) };
};

// ---------- blocked threats (banIP) ----------

export function threats() {
	let st = hub.run('/etc/init.d/banip status 2>/dev/null');
	if (!length(st)) return { available: false };
	let field = name => { let m = match(st, regexp(`\\+ ${name} *: ([^\\n]*)`)); return m ? trim(m[1]) : null; };
	let by = hub.names_by_ip(), hits = {}, total = 0;
	for (let line in split(hub.run("logread -e 'banIP/'"), '\n')) {
		let m = match(line, /banIP\/([a-z]+)\/[a-z]+\/([A-Za-z0-9._-]+): .*SRC=([0-9a-f.:]+) DST=([0-9a-f.:]+)/);
		if (!m) continue;
		total++;
		let who = m[1] == 'outbound' ? m[3] : m[4], k = who + '|' + m[2];
		hits[k] = hits[k] ?? { device: by[who] ?? who, ip: who, list: replace(m[2], /\.v[46]$/, ''), direction: m[1], count: 0 };
		hits[k].count++;
	}
	let rows = sort(values(hits), (a, b) => b.count - a.count);
	let count = match(field('element_count') ?? '', /^([0-9 ]+)/);
	return { available: true, active: match(field('status') ?? '', /^active/) != null,
		entries: count ? +replace(count[1], / /g, '') : 0,
		lists: uniq(filter(map(split(field('active_feeds') ?? '', ','), x => replace(trim(x), /\.v[46](MAC)?$/, '')), x => length(x) && !match(x, /^(allow|block)list/))),
		recent_total: total, recent: slice(rows, 0, 15) };
};

// ---------- connection test ----------

function ping(host, v6) {
	if (!match(host, /^[0-9a-fA-F:.]+$/)) return null;
	let m = match(hub.run(`ping ${v6 ? '-6' : '-4'} -c 2 -W 2 ${host} 2>/dev/null`), /min\/avg\/max = [0-9.]+\/([0-9.]+)\//);
	return m ? +m[1] : null;
}

export function diagnose() {
	let conn = connect(), wan = conn.call('network.interface.wan', 'status') ?? {}, wan6 = conn.call('network.interface.wan6', 'status') ?? {};
	let steps = [];
	let add = (name, ok, detail) => push(steps, { name, ok, detail });
	add('Cable to the provider', !!wan.up, wan.up ? `Connected, address ${(wan['ipv4-address'] ?? [ {} ])[0]?.address ?? 'none'}` : 'The router has no connection on its internet port.');
	let gw = null;
	for (let r in (wan.route ?? [])) if (r.target == '0.0.0.0' && r.nexthop) gw = r.nexthop;
	if (gw) { let t = ping(gw); add('Provider\'s gateway', t != null, t != null ? `Answers in ${t} ms` : 'No answer from the provider\'s first hop.'); }
	let t1 = ping('1.1.1.1'), t2 = t1 == null ? ping('9.9.9.9') : null;
	add('Internet', t1 != null || t2 != null, t1 != null || t2 != null ? `Answers in ${t1 ?? t2} ms` : 'No answer from the internet.');
	let dns = match(hub.run('nslookup -timeout=3 openwrt.org 127.0.0.1 2>/dev/null'), /Address[^\n]*\n(.|\n)*Address/) != null;
	add('Name lookups (DNS)', dns, dns ? 'Working' : 'Names cannot be looked up, so websites will not open.');
	if (wan6.up) { let t = ping('2606:4700:4700::1111', true); add('IPv6', t != null, t != null ? `Answers in ${t} ms` : 'IPv6 is set up but not answering.'); }
	let rproc = hub.load(RUN + '/status.json', {}).wifi?.cores ?? {};
	let bad = filter(keys(rproc), k => rproc[k] != 'running');
	add('Wi-Fi radios', !length(bad), length(bad) ? 'A Wi-Fi radio has crashed.' : 'Running');
	return { ok: length(filter(steps, s => !s.ok)) == 0, steps };
};

// ---------- overview of what protects the network ----------

export function overview() {
	let c = cursor(), conn = connect(), forwards = [], sqm = [], dns_forced = false, zones = [];
	c.foreach('firewall', 'redirect', r => {
		if (r.target == 'SNAT') return;
		if (r.src == 'wan') push(forwards, { name: r.name ?? 'Port forward', port: r.src_dport, to: `${r.dest_ip ?? ''}${r.dest_port ? ':' + r.dest_port : ''}`, proto: type(r.proto) == 'array' ? join(' ', r.proto) : r.proto });
		else if (r.src_dport == '53') dns_forced = true;
	});
	c.foreach('firewall', 'zone', z => { if (z.name != 'wan') push(zones, NET_LABEL[z.name] ?? z.name); });
	c.foreach('sqm', 'queue', q => { if (q.enabled == '1') push(sqm, { interface: q.interface, down: +(q.download ?? 0), up: +(q.upload ?? 0) }); });
	let wg = [];
	for (let i in (conn.call('network.interface', 'dump')?.interface ?? []))
		if (i.proto == 'wireguard') push(wg, { name: i.interface, up: !!i.up });
	let limit = 0;
	for (let q in sqm) limit = max(limit, q.down, q.up);
	return {
		firewall: true, networks: zones, port_forwards: forwards, upnp: c.get('upnpd', 'config', 'enabled') == '1',
		dns_forced, traffic_shaping: { enabled: length(sqm) > 0, limit_kbit: limit },
		vpn: wg, ssh_password: c.get('dropbear', 'main', 'PasswordAuth') != 'off'
	};
};

// ---------- the week in one screen ----------

export function week() {
	let now = time(), since = now - 7 * 86400;
	let alerts = filter(hub.alerts(300), a => a.ts >= since), kinds = {};
	for (let a in alerts) if (a.severity != 'info') kinds[a.kind] = (kinds[a.kind] ?? 0) + 1;
	let devs = hub.load(RUN + '/devices.json', {}).devices ?? [];
	let days = slice(hub.usage_history(), -7), down = 0, up = 0, top = {};
	for (let d in days) {
		down += d.total.down; up += d.total.up;
		for (let t in d.top) { top[t.name] = (top[t.name] ?? 0) + t.down + t.up; }
	}
	if (!length(days))   // no finished day yet: show today so far
		for (let d in devs) { down += d.today?.down ?? 0; up += d.today?.up ?? 0; if ((d.today?.down ?? 0) + (d.today?.up ?? 0) > 0) top[d.name] = d.today.down + d.today.up; }
	// devices found when the list was first built are not "new"
	let first = now;
	for (let d in devs) if (d.first_seen && d.first_seen < first) first = d.first_seen;
	since = max(since, first + 900);
	let st = hub.load(RUN + '/status.json', {});
	return {
		days: map(days, d => ({ day: d.day, down: d.total.down, up: d.total.up })), down, up,
		top_devices: slice(sort(map(keys(top), k => ({ name: k, bytes: top[k] })), (a, b) => b.bytes - a.bytes), 0, 5),
		new_devices: map(filter(devs, d => (d.first_seen ?? 0) >= since), d => ({ name: d.name, mac: d.mac })),
		problems: { internet: kinds.internet ?? 0, radio: kinds.radio ?? 0, dns: kinds.dns ?? 0, router: kinds.router ?? 0 },
		alerts: length(alerts), router_uptime: st.router?.uptime, devices_known: length(devs)
	};
};

// ---------- speed test (from the router itself) ----------

const SPEEDTESTS = ETC + '/speedtests.json';

function uptime_ms() {
	return int(+split(readfile('/proc/uptime') ?? '0', ' ')[0] * 1000);
}

/* Four parallel 60 MB downloads from Cloudflare. Measures the line from the router, so Wi-Fi does not
   affect it. Very fast lines read a little low because the router's own processor becomes the limit. */
export function speedtest() {
	let n = 4, bytes = 60000000, a = uptime_ms();
	let out = hub.run(`for i in 1 2 3 4; do (uclient-fetch -q -T 20 -O /dev/null 'https://speed.cloudflare.com/__down?bytes=${bytes}' && echo ok) & done; wait`);
	let ms = uptime_ms() - a, ok = length(filter(split(out, '\n'), l => l == 'ok'));
	if (ok == 0 || ms <= 0) return { error: 'The test server did not answer. Is the internet up?' };
	let t0 = uptime_ms();
	let ping = match(hub.run('ping -4 -c 3 -W 2 1.1.1.1 2>/dev/null'), /min\/avg\/max = [0-9.]+\/([0-9.]+)\//);
	let r = { ts: time(), down_bps: int(ok * bytes * 8 * 1000 / ms), ping_ms: ping ? +ping[1] : null, partial: ok < n };
	hub.locked(() => {
		let h = hub.load(SPEEDTESTS, []);
		push(h, r);
		hub.save(SPEEDTESTS, slice(h, max(0, length(h) - 60)));
	});
	return r;
};

export function speedtests() {
	return hub.load(SPEEDTESTS, []);
};

// ---------- Wi-Fi check: neighbours per channel, and devices with a weak link ----------

export function wifi_check() {
	let conn = connect(), radios = [];
	for (let rname, r in (conn.call('network.wireless', 'status') ?? {})) {
		let ifname = null;
		for (let i in (r.interfaces ?? [])) if (i.ifname && !ifname) ifname = i.ifname;
		if (!ifname) continue;
		let info = conn.call('iwinfo', 'info', { device: ifname }) ?? {};
		let scan = conn.call('iwinfo', 'scan', { device: ifname })?.results ?? [];
		let per = {};
		for (let n in scan) {
			if (!n.channel) continue;
			let k = '' + n.channel;
			per[k] = per[k] ?? { channel: n.channel, networks: 0, strongest: -100 };
			per[k].networks++;
			if ((n.signal ?? -100) > per[k].strongest) per[k].strongest = n.signal;
		}
		let band24 = (info.frequency ?? 0) < 4000, advice = null, best = null;
		if (band24) {
			// only 1, 6 and 11 do not overlap; a neighbour within 4 channels still interferes
			let crowd = c => { let t = 0; for (let k, v in per) if ((v.channel > c ? v.channel - c : c - v.channel) <= 4) t += v.networks * (v.strongest > -70 ? 2 : 1); return t; };
			let cand = sort(map([ 1, 6, 11 ], c => ({ channel: c, load: crowd(c) })), (a, b) => a.load - b.load);
			best = cand[0].channel;
			let cur = crowd(info.channel);
			advice = (best == info.channel || cur <= cand[0].load + 1)
				? `Channel ${info.channel} is a good choice here.`
				: `Channel ${best} has less interference than channel ${info.channel}. Zigbee smart-home networks on channel 25 sit next to Wi-Fi channel 11, so prefer 1 or 6 if you have one.`;
		} else {
			advice = `${length(scan)} neighbouring network${length(scan) == 1 ? '' : 's'} seen on 5 GHz. With a wide ${info.htmode ?? ''} channel there is little to gain from moving.`;
		}
		push(radios, { band: band24 ? '2.4 GHz' : '5 GHz', channel: info.channel, width: info.htmode, neighbours: length(scan), suggested: best, advice,
			channels: sort(values(per), (a, b) => a.channel - b.channel) });
	}
	let weak = [];
	for (let d in (hub.load(RUN + '/devices.json', {}).devices ?? []))
		if (d.online && d.link?.signal != null && d.link.signal < -72)
			push(weak, { name: d.name, mac: d.mac, signal: d.link.signal, band: d.link.band,
				advice: d.link.band == '5 GHz' ? 'Far from the router for 5 GHz. Move it closer, or let it use 2.4 GHz.' : 'Weak signal. Move it closer to the router or away from metal and walls.' });
	return { radios, weak: sort(weak, (a, b) => a.signal - b.signal) };
};

// ---------- wake a sleeping device ----------

export function wake(mac) {
	if (!hub.is_mac(mac)) return 'unknown device';
	return system([ '/usr/sbin/miwrt-wol', mac ]) == 0 ? null : 'Could not send the wake-up signal.';
};
