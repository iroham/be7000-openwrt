// MiWRT hub: the router-side service behind the MiWRT app.
// Collects the router's state, keeps the device list and the alert inbox, and applies the
// few changes the app can make (device names, paused devices, lights, restart).
'use strict';

import { readfile, writefile, popen, stat, lsdir, rename, mkdir, open, unlink, access } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';
import * as digest from 'digest';

export const VERSION = '0.8';
const ETC = '/etc/miwrt';
const RUN = '/tmp/miwrt';
const DEVICES = ETC + '/devices.json';
const TOKENS = ETC + '/tokens.json';
const ALERTS = ETC + '/alerts.jsonl';
const SETTINGS = ETC + '/settings.json';
const BLOCKED_NFT = ETC + '/blocked.nft';
const WATCHDOG = ETC + '/watchdog.json';
const GROUPS = ETC + '/groups.json';
const SCHEDULES = ETC + '/schedules.json';
const USAGE = ETC + '/usage.json';
const BLOCKED_LIST = ETC + '/blocked.list';
const PUSH_QUEUE = RUN + '/push-queue.jsonl';
const HISTORY = RUN + '/history.json';
export const PUSH_KINDS = [ 'radio', 'internet', 'dns', 'device', 'router' ];
const OUI = '/usr/share/miwrt/oui.txt';

// category -> default SF Symbol shown by the app
export const CATEGORIES = {
	phone: 'iphone', tablet: 'ipad', computer: 'laptopcomputer', tv: 'tv', speaker: 'hifispeaker',
	camera: 'web.camera', appliance: 'washer', heating: 'heater.vertical', lighting: 'lightbulb',
	hub: 'homekit', switch: 'switch.2', console: 'gamecontroller', printer: 'printer',
	storage: 'externaldrive', network: 'wifi.router', server: 'cpu', wearable: 'applewatch', other: 'questionmark.circle'
};
export const ICONS = [
	'air.conditioner.horizontal', 'airpodspro', 'appletv', 'applewatch', 'cable.connector', 'car', 'cpu', 'desktopcomputer',
	'dishwasher', 'door.garage.closed', 'dryer', 'externaldrive', 'externaldrive.connected.to.line.below', 'fan',
	'gamecontroller', 'heater.vertical', 'hifispeaker', 'homekit', 'homepod', 'homepodmini', 'ipad', 'iphone', 'lamp.desk',
	'laptopcomputer', 'light.panel', 'lightbulb', 'lightbulb.led', 'lock', 'macmini', 'oven', 'playstation.logo', 'powerplug',
	'printer', 'questionmark.circle', 'refrigerator', 'robotic.vacuum', 'sensor', 'server.rack', 'switch.2',
	'thermometer.medium', 'tv', 'video.doorbell', 'washer', 'web.camera', 'wifi', 'wifi.router', 'xbox.logo'
];
const GUESS = [
	[ /raspberry|server/, 'server' ],
	[ /iphone|pixel|galaxy s|oneplus/, 'phone' ], [ /ipad|tablet/, 'tablet' ],
	[ /(^|[^a-z])mac($|[^a-z])|macbook|imac|laptop|desktop|windows|thinkpad/, 'computer' ],
	[ /(^|[^a-z])tv($|[^a-z])|bravia|webos|chromecast|fire ?tv|roku|apple-?tv/, 'tv' ],
	[ /echo|alexa|homepod|sonos|google|nest/, 'speaker' ], [ /eufy|anker|camera|doorbell|ring/, 'camera' ],
	[ /laundry|wash|dryer|fridge|oven|dishwasher|lg innotek/, 'appliance' ], [ /ntr-|rointe|heater|thermostat|tado/, 'heating' ],
	[ /govee|hue|bulb|light|lifx/, 'lighting' ], [ /tuya|moes|zigbee|gateway|smartthings/, 'hub' ],
	[ /espressif|shelly|sonoff|plug|switch/, 'switch' ], [ /playstation|xbox|nintendo/, 'console' ],
	[ /printer|epson|canon|brother/, 'printer' ], [ /(^|[^a-z])nas($|[^a-z])|synology|ugreen|qnap/, 'storage' ],
	[ /router|access point/, 'network' ], [ /watch/, 'wearable' ]
];

// ---------- small helpers ----------

export function load(path, fallback) {
	let raw = readfile(path);
	if (!raw) return fallback;
	try { return json(raw); } catch (e) { return fallback; }
};

function tmpname(path) {
	return `${path}.${hexenc(open('/dev/urandom', 'r').read(4))}.tmp`;
}

export function save(path, obj) {
	let t = tmpname(path);
	writefile(t, sprintf('%J', obj));
	rename(t, path);
};

export function save_private(path, obj) {
	let t = tmpname(path);
	writefile(t, '');
	system([ 'chmod', '600', t ]);
	writefile(t, sprintf('%J', obj));
	rename(t, path);
}

// One writer at a time: the 30 s pass and requests from the app both change the same files.
let lock_held = false;
export function locked(fn) {
	if (lock_held) return fn();
	mkdir(RUN);
	let f = open(RUN + '/lock', 'w');
	if (f) f.lock('x');
	lock_held = true;
	let out, err = null;
	try { out = fn(); } catch (e) { err = e; }
	lock_held = false;
	if (f) { f.lock('u'); f.close(); }
	if (err) die(err);
	return out;
}

function read_trim(path) {
	return trim(readfile(path) ?? '');
}

export function run(cmd) {
	let p = popen(cmd, 'r');
	if (!p) return '';
	let out = p.read('all') ?? '';
	p.close();
	return out;
}

/* How notifications leave the router: 'direct' (this router holds an Apple push key and talks to Apple itself),
   'relay' (a relay holds the key), or null (neither is set up). */
/* The relay a router uses when it has no push key of its own. Empty: none. A relay set in the settings wins. */
export const DEFAULT_RELAY = 'https://miwrt-relay.iroham.cloud';
export const APNS_KEY = '/etc/miwrt/apns/key.p8';
export const APNS_CONF = '/etc/miwrt/apns/config.json';
export function push_mode(p) {
	if (access(APNS_KEY, 'r') && access(APNS_CONF, 'r') && access('/usr/bin/curl', 'x')) return 'direct';
	return (p?.relay || length(DEFAULT_RELAY)) ? 'relay' : null;
};


export function is_mac(s) {
	return type(s) == 'string' && match(s, /^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/) != null;
};

function is_private_mac(mac) {
	return index('26ae', substr(mac, 1, 1)) >= 0;
}

function ip2int(ip) {
	let p = split(ip ?? '', '.');
	if (length(p) != 4) return null;
	return ((+p[0]) << 24) + ((+p[1]) << 16) + ((+p[2]) << 8) + (+p[3]);
}

export function host_slug(name) {
	let s = replace(trim(name ?? ''), /[^A-Za-z0-9]+/g, '-');
	s = replace(s, /^-+|-+$/g, '');
	return length(s) ? substr(s, 0, 48) : null;
};

function vendor_of(mac) {
	if (is_private_mac(mac)) return null;
	let prefix = replace(substr(mac, 0, 8), /:/g, '');
	if (!match(prefix, /^[0-9a-f]{6}$/) || !stat(OUI)) return null;
	let line = trim(run(`grep -m1 '^${prefix}' ${OUI}`));
	return length(line) > 7 ? substr(line, 7) : null;
}

function guess_category(d) {
	let text = lc(join(' ', filter([ d.custom_name, d.name, d.vendor ], x => x != null)));
	for (let g in GUESS)
		if (match(text, g[0])) return g[1];
	return 'other';
}

// ---------- alerts ----------

export function alerts(limit) {
	let out = [];
	for (let line in split(readfile(ALERTS) ?? '', '\n')) {
		if (!length(line)) continue;
		try { push(out, json(line)); } catch (e) {}
	}
	out = reverse(out);
	return slice(out, 0, limit ?? 200);
};

export function add_alert(kind, title, body, severity, key, quiet) {
	let now = time(), all = alerts(300);
	if (key)
		for (let a in all)
			if (a.key == key && now - a.ts < (quiet ?? 900)) return;
	let a = { id: hexenc(open('/dev/urandom', 'r').read(6)), ts: now, kind, severity: severity ?? 'warning', title, body: body ?? '', key };
	let keep = reverse(slice(all, 0, 299));
	push(keep, a);
	let t = tmpname(ALERTS);
	writefile(t, join('\n', map(keep, x => sprintf('%J', x))) + '\n');
	rename(t, ALERTS);
	// notifications: queue it and let the sender run in the background
	let p = load(SETTINGS, {}).push;
	if (p?.enabled && push_mode(p)) {
		let f = open(PUSH_QUEUE, 'a');
		if (f) { f.write(sprintf('%J', a) + '\n'); f.close(); }
		system('/usr/sbin/miwrt-push >/dev/null 2>&1 &');
	}
};

// ---------- collecting the router's state ----------

function ucfirst(s) {
	return uc(substr(s, 0, 1)) + substr(s, 1);
}

function networks(conn) {
	// LAN-side interfaces with their IPv4 subnets, used to label a device's network
	let out = [];
	let labels = { lan: 'Main', iot: 'IoT', guest: 'Guest' };
	for (let i in (conn.call('network.interface', 'dump')?.interface ?? [])) {
		if (i.interface in [ 'loopback', 'wan', 'wan6' ] || match(i.interface, /^wan/)) continue;
		for (let a in (i['ipv4-address'] ?? [])) {
			let mask = a.mask >= 32 ? 0xffffffff : (0xffffffff << (32 - a.mask)) & 0xffffffff;
			push(out, { name: labels[i.interface] ?? ucfirst(i.interface), net: ip2int(a.address) & mask, mask });
		}
	}
	return out;
}

function net_of(nets, ip) {
	let n = ip2int(ip);
	if (n == null) return 'Not connected';
	for (let x in nets)
		if ((n & x.mask) == x.net) return x.name;
	return 'Other';
}

function collect(conn) {
	let s = { ts: time() };
	s.board = conn.call('system', 'board') ?? {};
	s.info = conn.call('system', 'info') ?? {};
	s.wan = conn.call('network.interface.wan', 'status') ?? {};
	s.wan6 = conn.call('network.interface.wan6', 'status') ?? {};
	s.leases = conn.call('luci-rpc', 'getDHCPLeases')?.dhcp_leases ?? [];
	s.hints = conn.call('luci-rpc', 'getHostHints') ?? {};
	s.nets = networks(conn);

	s.wifi = [];
	let wl = conn.call('network.wireless', 'status') ?? {};
	for (let radio, r in wl)
		for (let i in (r.interfaces ?? [])) {
			if (!i.ifname) continue;
			let info = conn.call('iwinfo', 'info', { device: i.ifname }) ?? {};
			let assoc = conn.call('iwinfo', 'assoclist', { device: i.ifname })?.results ?? [];
			push(s.wifi, { ifname: i.ifname, info, assoc });
		}

	// who sits on which cable port
	s.wired = {};
	s.own = {};
	for (let dev in (lsdir('/sys/class/net') ?? [])) {
		let addr = read_trim(`/sys/class/net/${dev}/address`);
		if (addr) s.own[addr] = true;
		if (!match(dev, /^[A-Za-z0-9_.-]+$/) || !stat(`/sys/class/net/${dev}/bridge`)) continue;
		let ports = {};
		for (let p in (lsdir(`/sys/class/net/${dev}/brif`) ?? []))
			ports[int(substr(read_trim(`/sys/class/net/${dev}/brif/${p}/port_no`), 2), 16)] = p;
		for (let line in split(run(`brctl showmacs ${dev} 2>/dev/null`), '\n')) {
			let f = split(trim(line), /\s+/);
			if (length(f) < 3 || f[2] != 'no' || !is_mac(f[1])) continue;
			let port = ports[+f[0]];
			if (port && !match(port, /^phy|^wl/)) s.wired[f[1]] = port;
		}
	}

	s.usage = {};
	try {
		let nl = json(run('nlbw -c json -g mac 2>/dev/null'));
		let c = nl.columns, im = index(c, 'mac'), ir = index(c, 'rx_bytes'), it = index(c, 'tx_bytes');
		for (let row in nl.data) s.usage[lc(row[im])] = { down: row[ir], up: row[it] };
	} catch (e) {}

	s.rproc = {};
	for (let r in (lsdir('/sys/class/remoteproc') ?? []))
		s.rproc[read_trim(`/sys/class/remoteproc/${r}/name`)] = read_trim(`/sys/class/remoteproc/${r}/state`);

	s.temp = 0;
	for (let z in (lsdir('/sys/class/thermal') ?? [])) {
		if (!match(z, /^thermal_zone/)) continue;
		let t = +read_trim(`/sys/class/thermal/${z}/temp`) / 1000;
		if (t > s.temp) s.temp = t;
	}

	let wdev = s.wan.l3_device ?? s.wan.device;
	s.wan_bytes = wdev ? { rx: +read_trim(`/sys/class/net/${wdev}/statistics/rx_bytes`), tx: +read_trim(`/sys/class/net/${wdev}/statistics/tx_bytes`) } : null;
	return s;
}

// ---------- talking to a linked ad blocker (used by the device list and the protection screens) ----------

function ag_call(cfg, path, payload) {
	if (!cfg || !match(cfg.url ?? '', /^https?:\/\/[A-Za-z0-9.-]+(:[0-9]{1,5})?$/)) return { code: 0, error: 'No ad blocker is linked.' };
	let id = hexenc(open('/dev/urandom', 'r').read(6));
	let errf = `${RUN}/ag-${id}.err`, bodyf = null;
	let cmd = `uclient-fetch -T 8 -O - --no-check-certificate --header='Authorization: Basic ${b64enc(cfg.username + ':' + cfg.password)}'`;
	if (payload != null) {
		bodyf = `${RUN}/ag-${id}.json`;
		writefile(bodyf, sprintf('%J', payload));
		cmd += ` --header='Content-Type: application/json' --post-file=${bodyf}`;
	}
	let out = run(`${cmd} '${cfg.url}${path}' 2>${errf}`);
	let err = readfile(errf) ?? '';
	unlink(errf);
	if (bodyf) unlink(bodyf);
	let m = match(err, /HTTP error ([0-9]{3})/);
	if (m) return { code: +m[1], error: (m[1] == '401' || m[1] == '403') ? 'The ad blocker rejected the user name or password.' : `The ad blocker answered with error ${m[1]}.` };
	if (!match(err, /Download completed/)) return { code: 0, error: 'Cannot reach the ad blocker at that address.' };
	let data = null;
	if (match(out, /^\s*[\[{]/)) { try { data = json(out); } catch (e) {} }
	return { code: 200, data, text: out };
}

/* One device's exemption from ad blocking: a client entry in AdGuard Home, keyed by its address. */
function adblock_client(mac, ip, label) {
	let cfg = load(ETC + '/adblock.json', null);
	if (!cfg) return 'Link an ad blocker first.';
	let name = 'MiWRT ' + mac;
	ag_call(cfg, '/control/clients/delete', { name });   // fine if it did not exist
	if (!ip) return null;
	if (!match(ip, /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/)) return 'This device has no usable address.';
	let r = ag_call(cfg, '/control/clients/add', { name, ids: [ ip ], use_global_settings: false, filtering_enabled: false,
		parental_enabled: false, safebrowsing_enabled: false, safesearch_enabled: false, use_global_blocked_services: true,
		blocked_services: [], upstreams: [], tags: [] });
	return r.code == 200 ? null : (r.error ?? 'The ad blocker refused that.');
}

// ---------- pausing: manual, waiting for approval, timers, groups, schedules ----------

export function settings() {
	let c = load(SETTINGS, {});
	let kinds = {};
	for (let k in PUSH_KINDS) kinds[k] = (c.push?.kinds ?? {})[k] !== false;
	return { watchdog: c.watchdog !== false, approve_new: !!c.approve_new, guest_until: c.guest_until ?? 0,
		push: { enabled: !!c.push?.enabled, relay: c.push?.relay ?? (length(DEFAULT_RELAY) ? DEFAULT_RELAY : null), kinds },
		night: { enabled: !!c.night?.enabled, from: c.night?.from ?? '23:00', to: c.night?.to ?? '07:00' } };
};

function minutes_of(hhmm) {
	let m = match(hhmm ?? '', /^([01][0-9]|2[0-3]):([0-5][0-9])$/);
	return m ? (+m[1]) * 60 + (+m[2]) : null;
}

export function schedule_active(sc, lt) {
	if (!sc.enabled) return false;
	let from = minutes_of(sc.from), to = minutes_of(sc.to), now = lt.hour * 60 + lt.min;
	if (from == null || to == null || from == to) return false;
	let today = lt.wday, yesterday = lt.wday == 1 ? 7 : lt.wday - 1;   // 1 = Monday .. 7 = Sunday
	if (from < to) return (today in sc.days) && now >= from && now < to;
	return ((today in sc.days) && now >= from) || ((yesterday in sc.days) && now < to);   // runs past midnight
}

/* mac -> reason, for every device that must not reach the internet right now */
function block_reasons(db, now) {
	let out = {}, groups = load(GROUPS, []), by_id = {};
	for (let mac, d in db) {
		if (d.blocked) out[mac] = 'paused';
		else if (d.pending) out[mac] = 'approval';
		else if ((d.pause_until ?? 0) > now) out[mac] = 'timer';
	}
	for (let g in groups) {
		by_id[g.id] = g;
		if (g.paused || (g.pause_until ?? 0) > now)
			for (let mac in g.macs) if (!(mac in out)) out[mac] = 'group';
	}
	let lt = localtime(now);
	for (let sc in load(SCHEDULES, [])) {
		if (!schedule_active(sc, lt)) continue;
		let macs = [ ...(sc.macs ?? []) ];
		for (let gid in (sc.groups ?? [])) if (by_id[gid]) push(macs, ...by_id[gid].macs);
		for (let mac in macs) if (!(mac in out)) out[mac] = 'schedule';
	}
	return out;
}

/* Write the pause list for the firewall, only when it changed. */
function sync_blocked(reasons) {
	let macs = sort(filter(keys(reasons), m => is_mac(m)));
	let want = join('\n', macs);
	if (want == trim(readfile(BLOCKED_LIST) ?? '') && stat(BLOCKED_NFT)) return;
	writefile(BLOCKED_NFT, length(macs) ? `ether saddr { ${join(', ', macs)} } counter reject comment "MiWRT: internet paused from the app"\n` : '');
	if (system([ 'fw4', 'check' ]) != 0) {
		writefile(BLOCKED_NFT, '');
		system('logger -t miwrt-hubd "pause list rejected by the firewall check, cleared"');
	}
	system([ 'fw4', '-q', 'reload' ]);
	writefile(BLOCKED_LIST, want + '\n');
}

// ---------- device list ----------

function merge_devices(s, db, rt) {
	let now = s.ts, dirty = false;
	let leases = {}, assoc = {};
	for (let l in s.leases) leases[lc(l.macaddr)] = l;
	let hints = {};
	for (let m, h in s.hints) hints[lc(m)] = h;
	for (let w in s.wifi) {
		let band = (w.info.frequency ?? 0) > 4000 ? '5 GHz' : '2.4 GHz';
		for (let a in w.assoc)
			assoc[lc(a.mac)] = { band, signal: a.signal, rx_rate: a.rx?.rate, tx_rate: a.tx?.rate, connected: a.connected_time };
	}

	let seen = {};
	for (let m in keys(assoc)) seen[m] = true;
	for (let m in keys(s.wired)) seen[m] = true;
	for (let m in keys(leases)) seen[m] = true;

	let live = {};
	for (let mac in keys(seen)) {
		if (s.own[mac] || match(mac, /^(01:00:5e|33:33|ff:ff)/)) continue;
		let online = (mac in assoc) || (mac in s.wired);
		let hip = hints[mac]?.ipaddrs;
		let ip = leases[mac]?.ipaddr ?? (hip ? hip[0] : null);
		if ((mac in s.wired) && ip && net_of(s.nets, ip) == 'Other') continue;   // the provider's gateway and the like
		if ((mac in s.wired) && !ip && !(mac in leases) && !(mac in db)) continue;

		let d = db[mac];
		if (!d) {
			d = db[mac] = { first_seen: now, vendor: vendor_of(mac) };
			dirty = true;
			if (!rt.learning && online) {
				let label = leases[mac]?.hostname ?? d.vendor ?? mac;
				let where = `the ${net_of(s.nets, ip)} network${(mac in assoc) ? ' (' + assoc[mac].band + ')' : ' (cable)'}`;
				if (settings().approve_new) {
					d.pending = true;
					add_alert('device', 'A new device is waiting for approval', `${label} joined ${where}. It has no internet until you allow it.`, 'warning', 'new-' + mac, 86400);
				} else {
					add_alert('device', 'New device joined', `${label} connected to ${where}.`, 'warning', 'new-' + mac, 86400);
				}
			}
		}
		let host = leases[mac]?.hostname ?? hints[mac]?.name;
		if (host && host != d.name) { d.name = host; dirty = true; }
		if (ip && ip != d.ip) {
			d.ip = ip; dirty = true;
			if (d.unfiltered && d.unfiltered != ip && !adblock_client(mac, ip, null)) d.unfiltered = ip;
		}
		if (online && now - (d.last_seen ?? 0) > 21600) { d.last_seen = now; dirty = true; }   // coarse on flash
		live[mac] = { online, link: assoc[mac] ?? ((mac in s.wired) ? { band: 'Cable', port: s.wired[mac] } : null), seen: online ? now : null };
	}
	if (!rt.last_seen) rt.last_seen = {};
	for (let mac, l in live) if (l.online) rt.last_seen[mac] = now;
	for (let mac, d in db)
		if (d.pause_until && d.pause_until <= now) { delete d.pause_until; dirty = true; }

	// forget devices nobody named that have not been seen for 90 days (rotating private addresses, guests)
	for (let mac in keys(db)) {
		let d = db[mac];
		if (!(mac in live) && !d.custom_name && !d.category && !d.icon && !d.blocked && !d.pending && !d.fixed_ip && !d.unfiltered && now - (d.last_seen ?? d.first_seen ?? now) > 90 * 86400) {
			delete db[mac];
			dirty = true;
		}
	}
	if (dirty) save(DEVICES, db);

	let reasons = block_reasons(db, now);
	sync_blocked(reasons);

	// live speed per device from the traffic counters, and today's totals
	let dt = now - (rt.usage_ts ?? 0), prev = rt.usage_prev ?? {}, rates = {};
	if (dt > 0 && dt < 300)
		for (let mac, u in s.usage) {
			let p = prev[mac];
			if (p && u.down >= p.down && u.up >= p.up) rates[mac] = { down: int((u.down - p.down) * 8 / dt), up: int((u.up - p.up) * 8 / dt) };
		}
	rt.usage_prev = s.usage; rt.usage_ts = now;
	let lt = localtime(now), day = sprintf('%04d-%02d-%02d', lt.year, lt.mon, lt.mday);
	if (rt.day != day) {
		if (rt.day && rt.day_base) {   // a day ended: keep its totals (one flash write a day)
			let hist = load(USAGE, []), total = { down: 0, up: 0 }, per = [];
			for (let mac, u in s.usage) {
				let b = rt.day_base[mac] ?? { down: 0, up: 0 };
				let dn = u.down >= b.down ? u.down - b.down : u.down, up = u.up >= b.up ? u.up - b.up : u.up;
				total.down += dn; total.up += up;
				if (dn + up > 0) push(per, { mac, down: dn, up });
			}
			per = slice(sort(per, (a, b) => (b.down + b.up) - (a.down + a.up)), 0, 10);
			push(hist, { day: rt.day, total, top: per });
			save(USAGE, slice(hist, max(0, length(hist) - 30)));
		}
		rt.day = day; rt.day_base = s.usage;
	}
	let groups = load(GROUPS, []);

	let out = [];
	for (let mac, d in db) {
		let l = live[mac] ?? { online: false, link: null };
		let cat = d.category ?? guess_category(d);
		push(out, {
			mac, vendor: d.vendor,
			name: d.custom_name ?? d.name ?? (d.vendor ? d.vendor + ' device' : 'Unnamed device'),
			hostname: d.name, ip: d.ip, network: d.ip ? net_of(s.nets, d.ip) : 'Not connected',
			online: l.online, link: l.link, usage: s.usage[mac], private_mac: is_private_mac(mac),
			category: cat, icon: d.icon ?? CATEGORIES[cat] ?? 'questionmark.circle',
			custom: !!(d.custom_name || d.category || d.icon),
			blocked: (mac in reasons), block_reason: reasons[mac], pending: !!d.pending, pause_until: d.pause_until,
			fixed_ip: !!d.fixed_ip, unfiltered: !!d.unfiltered, groups: map(filter(groups, g => (mac in g.macs)), g => g.id),
			rate: rates[mac], today: (() => {
				let u = s.usage[mac], b = (rt.day_base ?? {})[mac];
				if (!u) return null;
				if (!b) return { down: u.down, up: u.up };
				return { down: u.down >= b.down ? u.down - b.down : u.down, up: u.up >= b.up ? u.up - b.up : u.up };
			})(),
			router_name_synced: d.custom_name ? (host_slug(d.custom_name) == d.name) : null,
			first_seen: d.first_seen, last_seen: rt.last_seen[mac] ?? d.last_seen
		});
	}
	let rank = d => (d.online ? '0' : '1') + d.network + lc(d.name);
	return sort(out, (a, b) => rank(a) < rank(b) ? -1 : (rank(a) > rank(b) ? 1 : 0));
}

function dns_ok() {
	// can the router itself resolve a name through its own resolver?
	return match(run('nslookup -timeout=2 openwrt.org 127.0.0.1 2>/dev/null'), /Address[^\n]*\n(.|\n)*Address/) != null;
}

function build_status(s, rt, devices) {
	let mem = s.info.memory ?? {};
	let radios = [];
	for (let w in s.wifi)
		push(radios, { ifname: w.ifname, ssid: w.info.ssid, band: (w.info.frequency ?? 0) > 4000 ? '5 GHz' : '2.4 GHz',
			channel: w.info.channel, width: w.info.htmode ?? '', txpower: w.info.txpower, clients: length(w.assoc) });
	let last = alerts(1);
	return {
		router: { reachable: true, age: 0, model: s.board.model, firmware: s.board.release?.description, hostname: s.board.hostname,
			uptime: s.info.uptime, load: map(s.info.load ?? [], x => x / 65536.0),
			memory_used_pct: mem.total ? int(100 - 100 * (mem.available ?? 0) / mem.total) : null,
			temperature: int(s.temp), leds: stat(ETC + '/leds-off') ? 'off' : 'on', can_control: true, updated: s.ts,
			watchdog: load(SETTINGS, {}).watchdog !== false },
		internet: { up: !!s.wan.up, ipv4: (s.wan['ipv4-address'] ?? [ {} ])[0]?.address, ipv6: !!s.wan6.up, uptime: s.wan.uptime,
			down_bps: rt.rates?.down ?? 0, up_bps: rt.rates?.up ?? 0 },
		wifi: { radios, cores: s.rproc },
		dns: { ok: rt.dns_ok },
		devices: { online: length(filter(devices, d => d.online)), known: length(devices), paused: length(filter(devices, d => d.blocked)),
			pending: length(filter(devices, d => d.pending)) },
		settings: settings(),
		alerts: { total: length(alerts(300)), last: last[0] }
	};
}

/* Alerts that only show up in the system log: radar on 5 GHz, a device that keeps failing to join, kernel trouble. */
function log_alerts(rt, db) {
	let lines = filter(split(run("logread -e 'DFS-RADAR-DETECTED|radar detected|did not acknowledge authentication|Kernel panic|Oops:|Out of memory'"), '\n'), l => length(l) > 0);
	let start = 0;
	if (rt.log_mark == null) start = length(lines);   // first pass after boot: old lines are history
	else {
		let i = rindex(lines, rt.log_mark);
		start = i >= 0 ? i + 1 : 0;
	}
	if (length(lines)) rt.log_mark = lines[length(lines) - 1];
	if (!rt.join_fail) rt.join_fail = {};
	let now = time();
	for (let line in slice(lines, start)) {
		if (match(line, /DFS-RADAR-DETECTED|radar detected/))
			add_alert('radio', 'Radar detected on 5 GHz', 'The router is moving 5 GHz to another channel. It may pause for about a minute.', 'warning', 'radar', 600);
		else if (match(line, /Kernel panic|Oops:|Out of memory/))
			add_alert('router', 'Router kernel error', 'The router logged a serious internal error.', 'critical', 'kernel', 3600);
		else {
			let m = match(line, /STA ([0-9a-f:]{17}) IEEE 802\.11: did not acknowledge/);
			if (!m) continue;
			let j = rt.join_fail[m[1]] ?? { since: now, n: 0 };
			if (now - j.since > 3600) j = { since: now, n: 0 };
			j.n++;
			rt.join_fail[m[1]] = j;
			if (j.n >= 30) {
				let d = db[m[1]] ?? {};
				add_alert('device', 'A device keeps failing to join Wi-Fi', `${d.custom_name ?? d.name ?? d.vendor ?? m[1]} tried ${j.n} times in the last hour. Weak signal or a faulty unit.`, 'info', 'joinfail-' + m[1], 86400);
				rt.join_fail[m[1]] = { since: now, n: 0 };
			}
		}
	}
}

/* Wi-Fi recovery: a crashed Wi-Fi core that does not come back by itself leaves its radio silent
   until the router restarts. After three passes (about 90 s) in that state the router restarts
   itself: not in the first 10 minutes after boot, and at most 3 times a day. */
function watchdog(s, rt) {
	if (!rt.rproc_bad) rt.rproc_bad = {};
	if (!rt.rproc_ran) rt.rproc_ran = {};
	let stuck = null;
	for (let name, st in s.rproc) {
		if (st == 'running') { rt.rproc_ran[name] = true; delete rt.rproc_bad[name]; continue; }
		if (!rt.rproc_ran[name]) continue;   // only a core that was working since boot counts as crashed
		rt.rproc_bad[name] = (rt.rproc_bad[name] ?? 0) + 1;
		if (rt.rproc_bad[name] >= 3) stuck = name;
	}
	if (!stuck || load(SETTINGS, {}).watchdog === false || (s.info.uptime ?? 0) < 600) return;
	let today = int(s.ts / 86400), wd = load(WATCHDOG, {});
	if (wd.day != today) wd = { day: today, count: 0 };
	if (wd.count >= 3) {
		add_alert('radio', 'Wi-Fi is down and the router will not restart again today', `Wi-Fi core ${stuck} keeps crashing. Three automatic restarts were already used today.`, 'critical', 'wd-giveup', 86400);
		return;
	}
	wd.count++;
	save(WATCHDOG, wd);
	add_alert('radio', 'Restarting the router to bring Wi-Fi back', `Wi-Fi core ${stuck} crashed and did not recover. Automatic restart ${wd.count} of 3 today.`, 'critical', 'wd-reboot', 300);
	system('logger -t miwrt-hubd "Wi-Fi core stuck, restarting the router"; (sleep 5; reboot) >/dev/null 2>&1 &');
}

// One pass: collect, detect changes, refresh the cached answers the app reads.
function tick_unlocked() {
	mkdir(ETC); mkdir(RUN);
	let conn = connect();
	let s = collect(conn);
	let rt = load(RUN + '/runtime.json', {});
	let first = !stat(DEVICES);
	let db = load(DEVICES, {});
	if (first) rt.learning_until = s.ts + 600;
	rt.learning = (rt.learning_until ?? 0) > s.ts;

	// internet speed from the WAN byte counters
	if (s.wan_bytes && rt.wan_bytes && s.ts > rt.wan_ts) {
		let dt = s.ts - rt.wan_ts, d = (s.wan_bytes.rx - rt.wan_bytes.rx) * 8 / dt, u = (s.wan_bytes.tx - rt.wan_bytes.tx) * 8 / dt;
		if (d >= 0 && u >= 0) rt.rates = { down: int(d), up: int(u) };
	}
	rt.wan_bytes = s.wan_bytes; rt.wan_ts = s.ts;

	let wan_up = !!s.wan.up;
	if (rt.wan_up != null && wan_up != rt.wan_up)
		wan_up ? add_alert('internet', 'Internet is back', '', 'info')
		       : add_alert('internet', 'Internet is down', 'The router lost its connection to the provider.', 'critical');
	rt.wan_up = wan_up;

	if (!rt.rproc) rt.rproc = {};
	for (let name, st in s.rproc) {
		let old = rt.rproc[name];
		if (old != null && st != old)
			st != 'running' ? add_alert('radio', 'Wi-Fi radio crashed', `Wi-Fi core ${name} is '${st}'. Its devices are offline until it restarts.`, 'critical', 'radio-down')
			                : add_alert('radio', 'Wi-Fi radio recovered', `Wi-Fi core ${name} is running again.`, 'info');
		rt.rproc[name] = st;
	}
	watchdog(s, rt);
	log_alerts(rt, load(DEVICES, {}));

	if (wan_up && (s.ts - (rt.dns_ts ?? 0)) >= 60) {
		let ok = dns_ok();
		if (rt.dns_ok === true && !ok) add_alert('dns', 'DNS is not answering', 'The router cannot look up names. Websites will not open.', 'critical', 'dns-down');
		if (rt.dns_ok === false && ok) add_alert('dns', 'DNS is back', '', 'info');
		rt.dns_ok = ok; rt.dns_ts = s.ts;
	}

	// lights off at night, back on in the morning (only if they were on)
	let st = settings(), lt_now = localtime(s.ts);
	let in_night = st.night.enabled && schedule_active({ enabled: true, from: st.night.from, to: st.night.to, days: [ 1, 2, 3, 4, 5, 6, 7 ] }, lt_now);
	if (in_night && !rt.night_on && !stat(ETC + '/leds-off')) { set_leds(false); rt.night_on = true; }
	else if (!in_night && rt.night_on) { set_leds(true); rt.night_on = false; }

	let devices = merge_devices(s, db, rt);
	// one sample every five minutes for the health charts (memory only, 48 hours)
	if (s.ts - (rt.hist_ts ?? 0) >= 300) {
		let mem = s.info.memory ?? {}, h = load(HISTORY, []);
		push(h, { ts: s.ts, temp: int(s.temp), mem: mem.total ? int(100 - 100 * (mem.available ?? 0) / mem.total) : null,
			down: rt.rates?.down ?? 0, up: rt.rates?.up ?? 0, clients: length(filter(devices, d => d.online)), wan: !!s.wan.up });
		save(HISTORY, slice(h, max(0, length(h) - 576)));
		rt.hist_ts = s.ts;
	}
	save(RUN + '/devices.json', { devices });
	save(RUN + '/status.json', build_status(s, rt, devices));
	save(RUN + '/runtime.json', rt);
}

export function tick() {
	return locked(tick_unlocked);
};

export function cached(name) {
	let st = stat(`${RUN}/${name}.json`);
	if (!st || time() - st.mtime > 90) tick();
	let out = load(`${RUN}/${name}.json`, {});
	if (name == 'status' && out.router) out.router.age = max(0, time() - (out.router.updated ?? time()));
	return out;
};

export function set_watchdog(on) {
	locked(() => {
		let c = load(SETTINGS, {});
		c.watchdog = !!on;
		save(SETTINGS, c);
	});
	tick();
};

// ---------- changes the app can make ----------

function apply_hosts(db) {
	let c = cursor(), old = [];
	c.foreach('dhcp', 'host', s => { if (match(s['.name'], /^miwrt_h_[0-9a-f]{12}$/)) push(old, s['.name']); });
	let manual = {};
	c.foreach('dhcp', 'host', s => { if (!match(s['.name'], /^miwrt_h_/)) for (let m in (type(s.mac) == 'array' ? s.mac : [ s.mac ])) if (m) manual[lc(m)] = true; });
	for (let sid in old) c.delete('dhcp', sid);
	for (let mac, d in db) {
		let slug = d.custom_name ? host_slug(d.custom_name) : null;
		let fixed = (d.fixed_ip && match(d.fixed_ip, /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/)) ? d.fixed_ip : null;
		if ((!slug && !fixed) || !is_mac(mac) || manual[mac]) continue;   // a lease made by hand in LuCI keeps its own settings
		let sid = 'miwrt_h_' + replace(mac, /:/g, '');
		c.set('dhcp', sid, 'host');
		c.set('dhcp', sid, 'mac', mac);
		if (slug ?? host_slug(d.name)) c.set('dhcp', sid, 'name', slug ?? host_slug(d.name));
		if (fixed) c.set('dhcp', sid, 'ip', fixed);
	}
	c.commit('dhcp');
	// The reload is done by the next 30 s pass, one at a time. Reloading from here could hit the address
	// server twice in a row, and a reload signal that arrives while it is still starting stops it.
	writefile(RUN + '/dnsmasq-reload', '1');
}


function update_device_unlocked(mac, b) {
	let db = load(DEVICES, {}), d = db[mac];
	if (!d) return 'unknown device';
	let hosts = false, block = false;
	if ('name' in b) {
		let n = (type(b.name) == 'string' && length(trim(b.name))) ? substr(trim(b.name), 0, 60) : null;
		if (n != d.custom_name) hosts = true;
		if (n) d.custom_name = n; else delete d.custom_name;
	}
	if ('category' in b) {
		if (b.category != null && !(b.category in CATEGORIES)) return 'unknown category';
		if (b.category) d.category = b.category; else delete d.category;
	}
	if ('icon' in b) {
		if (b.icon != null && !(b.icon in ICONS)) return 'unknown icon';
		if (b.icon) d.icon = b.icon; else delete d.icon;
	}
	let label = d.custom_name ?? d.name ?? d.vendor ?? mac;
	if ('blocked' in b) {
		block = (!!b.blocked != !!d.blocked);
		if (b.blocked) d.blocked = true; else { delete d.blocked; delete d.pause_until; }
		if (block) add_alert('device', d.blocked ? 'Internet paused' : 'Internet resumed', label, 'info');
	}
	if ('pause_minutes' in b) {
		let m = int(+b.pause_minutes);
		if (m < 0 || m > 10080) return 'Choose between 1 minute and 7 days.';
		if (m > 0) { d.pause_until = time() + m * 60; add_alert('device', 'Internet paused for a while', `${label}, for ${m >= 60 ? int(m / 60) + ' h' : m + ' min'}.`, 'info'); }
		else delete d.pause_until;
	}
	if ('approve' in b && d.pending) {
		delete d.pending;
		if (!b.approve) d.blocked = true;
		add_alert('device', b.approve ? 'Device allowed' : 'Device blocked', label, 'info');
	}
	if ('filtering' in b) {
		// "off": this device bypasses ad blocking (a named client in the linked ad blocker); "on": back to normal
		let off = b.filtering == 'off';
		if (off && !d.ip) return 'This device has no address yet.';
		let err = adblock_client(mac, off ? d.ip : null, label);
		if (err) return err;
		if (off) d.unfiltered = d.ip; else delete d.unfiltered;
		add_alert('device', off ? 'Ad blocking turned off for a device' : 'Ad blocking back on for a device', label, 'info');
	}
	if ('fixed_ip' in b) {
		if (b.fixed_ip && !d.ip) return 'This device has no address yet.';
		if (!!b.fixed_ip != !!d.fixed_ip) hosts = true;
		if (b.fixed_ip) d.fixed_ip = d.ip; else delete d.fixed_ip;
	}
	save(DEVICES, db);
	if (hosts) apply_hosts(db);
	tick_unlocked();
	return null;
}

export function update_device(mac, b) {
	return locked(() => update_device_unlocked(mac, b));
};

export function random_bytes(n) {
	let f = open('/dev/urandom', 'r'), raw = f.read(n);
	f.close();
	return raw;
};

function new_id() {
	return hexenc(open('/dev/urandom', 'r').read(4));
}

function clean_macs(list, db) {
	let out = [];
	for (let m in (type(list) == 'array' ? list : []))
		if (is_mac(m) && (m in db) && !(m in out)) push(out, m);
	return slice(out, 0, 200);
}

function clean_name(n) {
	n = replace(trim(type(n) == 'string' ? n : ''), /[[:cntrl:]]/g, '');
	return length(n) ? substr(n, 0, 40) : null;
}

export function groups_list() {
	let devs = load(RUN + '/devices.json', {}).devices ?? [], by = {}, now = time();
	for (let d in devs) by[d.mac] = d;
	return map(load(GROUPS, []), g => {
		let members = filter(map(g.macs, m => by[m]), d => d != null);
		return { ...g, paused: !!g.paused || (g.pause_until ?? 0) > now,
			online: length(filter(members, d => d.online)),
			home: g.kind == 'person' ? length(filter(members, d => d.online && (d.category in [ 'phone', 'wearable' ]))) > 0 : null };
	});
};

export function groups_action(b) {
	return locked(() => {
		let all = load(GROUPS, []), db = load(DEVICES, {});
		if (b.action == 'save') {
			let name = clean_name(b.name);
			if (!name) return 'Give it a name.';
			let g = { id: null, name, kind: b.kind == 'room' ? 'room' : 'person',
				icon: (b.icon in ICONS) || (b.icon in [ 'person.fill', 'figure.child', 'house.fill', 'sofa.fill', 'bed.double.fill', 'fork.knife' ]) ? b.icon : null,
				macs: clean_macs(b.macs, db) };
			let i = index(map(all, x => x.id), b.id);
			if (i >= 0) { g.id = all[i].id; g.paused = all[i].paused; g.pause_until = all[i].pause_until; all[i] = g; }
			else { if (length(all) >= 30) return 'That is the most groups you can have.'; g.id = new_id(); push(all, g); }
		} else if (b.action == 'delete') {
			all = filter(all, x => x.id != b.id);
			let scs = load(SCHEDULES, []);
			for (let sc in scs) sc.groups = filter(sc.groups ?? [], x => x != b.id);
			save(SCHEDULES, scs);
		} else if (b.action == 'pause') {
			let i = index(map(all, x => x.id), b.id);
			if (i < 0) return 'That group no longer exists.';
			let m = int(+(b.minutes ?? 0));
			if (m < 0 || m > 10080) return 'Choose between 1 minute and 7 days.';
			delete all[i].pause_until;
			all[i].paused = !!b.paused && m == 0;
			if (b.paused && m > 0) all[i].pause_until = time() + m * 60;
			add_alert('device', b.paused ? 'Group paused' : 'Group resumed', all[i].name + (m > 0 ? `, for ${m >= 60 ? int(m / 60) + ' h' : m + ' min'}` : ''), 'info');
		} else return 'unknown action';
		save(GROUPS, all);
		tick_unlocked();
		return null;
	});
};

export function schedules_list() {
	let lt = localtime();
	return map(load(SCHEDULES, []), sc => ({ ...sc, active: schedule_active(sc, lt) }));
};

export function schedules_action(b) {
	return locked(() => {
		let all = load(SCHEDULES, []), db = load(DEVICES, {}), gids = map(load(GROUPS, []), g => g.id);
		if (b.action == 'save') {
			let name = clean_name(b.name);
			if (!name) return 'Give it a name.';
			if (minutes_of(b.from) == null || minutes_of(b.to) == null || b.from == b.to) return 'Choose a start and an end time that differ.';
			let days = sort(filter(type(b.days) == 'array' ? b.days : [], d => type(d) == 'int' && d >= 1 && d <= 7));
			if (!length(days)) return 'Choose at least one day.';
			let sc = { id: null, name, from: b.from, to: b.to, days, enabled: b.enabled !== false,
				macs: clean_macs(b.macs, db), groups: filter(type(b.groups) == 'array' ? b.groups : [], g => (g in gids)) };
			if (!length(sc.macs) && !length(sc.groups)) return 'Choose at least one device or group.';
			let i = index(map(all, x => x.id), b.id);
			if (i >= 0) { sc.id = all[i].id; all[i] = sc; }
			else { if (length(all) >= 30) return 'That is the most schedules you can have.'; sc.id = new_id(); push(all, sc); }
		} else if (b.action == 'delete') {
			all = filter(all, x => x.id != b.id);
		} else return 'unknown action';
		save(SCHEDULES, all);
		tick_unlocked();
		return null;
	});
};

export function set_setting(b) {
	return locked(() => {
		let c = load(SETTINGS, {});
		if ('approve_new' in b) c.approve_new = !!b.approve_new;
		if ('watchdog' in b) c.watchdog = !!b.watchdog;
		if (type(b.push) == 'object') {
			let p = c.push ?? {};
			if ('enabled' in b.push) p.enabled = !!b.push.enabled;
			if ('relay' in b.push) {
				let r = replace(trim(b.push.relay ?? ''), /\/+$/, '');
				if (length(r) && !match(r, /^https?:\/\/[A-Za-z0-9.-]+(:[0-9]{1,5})?$/)) return 'The relay address does not look right.';
				p.relay = length(r) ? r : null;
			}
			if (type(b.push.kinds) == 'object') {
				p.kinds = p.kinds ?? {};
				for (let k in PUSH_KINDS) if (k in b.push.kinds) p.kinds[k] = !!b.push.kinds[k];
			}
			c.push = p;
		}
		if (type(b.night) == 'object') {
			let n = c.night ?? {};
			if ('enabled' in b.night) n.enabled = !!b.night.enabled;
			for (let k in [ 'from', 'to' ]) if (k in b.night) {
				if (minutes_of(b.night[k]) == null) return 'Times look like 23:00.';
				n[k] = b.night[k];
			}
			if (n.from == n.to && n.enabled) return 'Choose a start and an end time that differ.';
			c.night = n;
		}
		save(SETTINGS, c);
		tick_unlocked();
		return null;
	});
};

export function usage_history() {
	let names = {};
	for (let d in (load(RUN + '/devices.json', {}).devices ?? [])) names[d.mac] = d.name;
	return map(load(USAGE, []), h => ({ day: h.day, total: h.total, top: map(h.top, t => ({ ...t, name: names[t.mac] ?? t.mac })) }));
};

export function set_leds(on) {
	if (!on) {
		if (!stat(ETC + '/leds-off')) {
			let saved = [];
			for (let l in (lsdir('/sys/class/leds') ?? [])) {
				let m = match(readfile(`/sys/class/leds/${l}/trigger`) ?? '', /\[([^\]]+)\]/);
				push(saved, { led: l, trigger: m ? m[1] : 'none', brightness: read_trim(`/sys/class/leds/${l}/brightness`) });
			}
			save(ETC + '/leds.saved', saved);
			writefile(ETC + '/leds-off', '');
		}
		for (let l in (lsdir('/sys/class/leds') ?? [])) {
			writefile(`/sys/class/leds/${l}/trigger`, 'none');
			writefile(`/sys/class/leds/${l}/brightness`, '0');
		}
	} else if (stat(ETC + '/leds-off')) {
		for (let x in load(ETC + '/leds.saved', [])) {
			if (!match(x.led, /^[A-Za-z0-9:._-]+$/) || !stat(`/sys/class/leds/${x.led}`)) continue;
			writefile(`/sys/class/leds/${x.led}/trigger`, x.trigger);
			if (x.trigger == 'none') writefile(`/sys/class/leds/${x.led}/brightness`, x.brightness);
		}
		unlink(ETC + '/leds-off');
	}
};

/* Re-apply what must survive a reboot (the lights; names and the pause list live in config files). */
export function boot() {
	mkdir(ETC); mkdir(RUN);
	if (!stat(BLOCKED_NFT)) writefile(BLOCKED_NFT, '');
	if (stat(ETC + '/leds-off')) set_leds(false);
};

// ---------- ad blocker link (AdGuard Home) ----------
// The app can link an AdGuard Home the user runs anywhere on the network. The router keeps the
// address and login (root-only file) and talks to AdGuard's own API on the app's behalf.

const ADBLOCK = ETC + '/adblock.json';

function is_domain(d) {
	return type(d) == 'string' && length(d) <= 253 && match(d, /^[A-Za-z0-9]([A-Za-z0-9_-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9_-]*[A-Za-z0-9])?)+$/) != null;
}


function ag() {
	return load(ADBLOCK, null);
}

export function protection_connect(b) {
	let url = replace(trim(b.url ?? ''), /\/+$/, '');
	if (!match(url, /^https?:\/\//)) url = 'http://' + url;
	if (!match(url, /^https?:\/\/[A-Za-z0-9.-]+(:[0-9]{1,5})?$/)) return 'That address does not look right. Use something like 192.168.1.2 or 192.168.1.2:3000.';
	if (type(b.username) != 'string' || !length(b.username) || type(b.password) != 'string') return 'Enter the ad blocker\'s user name and password.';
	if (match(b.username, /[:\n\r]/) || match(b.password, /[\n\r]/)) return 'The user name or password contains characters that cannot be used.';
	let cfg = { provider: 'adguard', url, username: b.username, password: b.password };
	let r = ag_call(cfg, '/control/status');
	if (r.code != 200) return r.error;
	if (!r.data || !('protection_enabled' in r.data)) return 'Something answers at that address, but it is not AdGuard Home.';
	save_private(ADBLOCK, cfg);
	unlink(RUN + '/protection.json');
	add_alert('dns', 'Ad blocker linked', `AdGuard Home ${r.data.version ?? ''} at ${replace(url, /^https?:\/\//, '')}.`, 'info');
	return null;
};

export function protection_disconnect() {
	unlink(ADBLOCK);
	unlink(RUN + '/protection.json');
};

function flat(rows, n) {
	let out = [];
	for (let row in slice(rows ?? [], 0, n))
		for (let k, v in row) push(out, { name: k, count: v });
	return out;
}

export function names_by_ip() {
	let by = {};
	for (let mac, d in load(DEVICES, {}))
		if (d.ip) by[d.ip] = d.custom_name ?? d.name ?? d.vendor ?? d.ip;
	return by;
}

function protection_changed() {
	unlink(RUN + '/protection.json');
}

function protection_fresh() {
	let cfg = ag();
	if (!cfg) return { configured: false };
	let st = ag_call(cfg, '/control/status');
	let base = { configured: true, provider: 'AdGuard Home', address: replace(cfg.url, /^https?:\/\//, '') };
	if (st.code != 200 || !st.data) return { ...base, error: st.error ?? 'The ad blocker gave an answer the router did not understand.' };
	let stats = ag_call(cfg, '/control/stats').data ?? {};
	let total = stats.num_dns_queries ?? 0, blocked = stats.num_blocked_filtering ?? 0, by = names_by_ip();
	return { ...base, enabled: !!st.data.protection_enabled, paused_ms: st.data.protection_disabled_duration ?? 0, version: st.data.version,
		queries: total, blocked, blocked_pct: total ? int(100 * blocked / total) : 0,
		avg_ms: int((stats.avg_processing_time ?? 0) * 10000) / 10.0,
		top_blocked: flat(stats.top_blocked_domains, 10),
		top_clients: map(flat(stats.top_clients, 10), c => ({ name: by[c.name] ?? c.name, ip: c.name, count: c.count })) };
}

/* The overview is asked for by every open app every few seconds; the ad blocker is only asked every 15 s. */
export function protection() {
	let st = stat(RUN + '/protection.json');
	if (st && time() - st.mtime < 15) return load(RUN + '/protection.json', { configured: false });
	let out = protection_fresh();
	save(RUN + '/protection.json', out);
	return out;
};

export function protection_pause(minutes) {
	let m = int(+minutes);
	if (m < 0 || m > 1440) return 'Choose between 1 minute and 24 hours.';
	let r = ag_call(ag(), '/control/protection', { enabled: m == 0, duration: m * 60000 });
	if (r.code != 200) return r.error;
	protection_changed();
	if (m > 0) add_alert('dns', 'Ad blocking paused', `Off for ${m} minutes, then back on by itself.`, 'info');
	return null;
};

function ag_filtering() {
	return ag_call(ag(), '/control/filtering/status');
}

export function protection_lists() {
	let r = ag_filtering();
	if (r.code != 200 || !r.data) return { error: r.error ?? 'No answer from the ad blocker.' };
	return {
		enabled: !!r.data.enabled,
		lists: map(r.data.filters ?? [], f => ({ id: f.id, name: f.name, url: f.url, enabled: !!f.enabled, rules: f.rules_count ?? 0, updated: f.last_updated })),
		rules: filter(r.data.user_rules ?? [], x => length(trim(x)) > 0)
	};
};

export function protection_list_action(b) {
	let cfg = ag(), r;
	if (b.action == 'refresh') {
		r = ag_call(cfg, '/control/filtering/refresh', { whitelist: false });
	} else {
		if (type(b.url) != 'string' || !match(b.url, /^https?:\/\/[^\s'"<>]{4,500}$/)) return 'A list needs a web address that starts with http:// or https://.';
		if (b.action == 'add')
			r = ag_call(cfg, '/control/filtering/add_url', { name: substr(trim(b.name ?? '') || 'Custom list', 0, 80), url: b.url, whitelist: false });
		else if (b.action == 'remove')
			r = ag_call(cfg, '/control/filtering/remove_url', { url: b.url, whitelist: false });
		else if (b.action == 'toggle')
			r = ag_call(cfg, '/control/filtering/set_url', { url: b.url, whitelist: false, data: { name: substr(b.name ?? '', 0, 80), url: b.url, enabled: !!b.enabled } });
		else return 'unknown action';
	}
	if (r.code != 200) return (r.code == 400) ? 'The ad blocker refused that list. Check the address, or it may already be added.' : r.error;
	return null;
};

/* allow or block one domain, or remove one of the user's own rules */
export function protection_rule_action(b) {
	let cur = ag_filtering();
	if (cur.code != 200 || !cur.data) return cur.error ?? 'No answer from the ad blocker.';
	let rules = filter(cur.data.user_rules ?? [], x => type(x) == 'string');
	if (b.action == 'remove') {
		if (type(b.rule) != 'string' || !(b.rule in rules)) return 'That rule is no longer there.';
		rules = filter(rules, x => x != b.rule);
	} else if (b.action == 'allow' || b.action == 'block') {
		let d = lc(trim(b.domain ?? ''));
		if (!is_domain(d)) return 'Enter a domain like example.com.';
		// drop any earlier rule of ours for the same domain, then add the new one
		let ours = [ `||${d}^`, `@@||${d}^`, `||${d}^$important`, `@@||${d}^$important` ];
		rules = filter(rules, x => !(x in ours));
		while (length(rules) && !length(trim(rules[length(rules) - 1]))) pop(rules);
		push(rules, b.action == 'allow' ? `@@||${d}^$important` : `||${d}^$important`);
	} else return 'unknown action';
	let r = ag_call(ag(), '/control/filtering/set_rules', { rules });
	return r.code == 200 ? null : r.error;
};

export function protection_log(which, search) {
	let q = '/control/querylog?limit=150&response_status=' + (which == 'blocked' ? 'filtered' : 'all');
	if (search != null && length(search)) {
		if (!match(search, /^[A-Za-z0-9._-]{1,100}$/)) return { error: 'Search for part of a domain, letters, digits and dots only.' };
		q += '&search=' + search;
	}
	let r = ag_call(ag(), q);
	if (r.code != 200 || !r.data) return { error: r.error ?? 'No answer from the ad blocker.' };
	let lists = { '0': 'Your own rules' };
	for (let f in (ag_filtering().data?.filters ?? [])) lists['' + f.id] = f.name;
	let by = names_by_ip(), out = [];
	for (let e in (r.data.data ?? [])) {
		let reason = e.reason ?? '', rule = (e.rules ?? [])[0];
		push(out, { time: e.time, domain: e.question?.name, type: e.question?.type, client: by[e.client] ?? e.client, ip: e.client,
			blocked: substr(reason, 0, 8) == 'Filtered', allowed_by_rule: reason == 'NotFilteredWhiteList',
			rule: rule?.text, list: rule ? (lists['' + rule.filter_list_id] ?? 'A blocklist') : null });
	}
	return { entries: out };
};

export function protection_check(domain) {
	let d = lc(trim(domain ?? ''));
	if (!is_domain(d)) return { error: 'Enter a domain like example.com.' };
	let r = ag_call(ag(), '/control/filtering/check_host?name=' + d);
	if (r.code != 200 || !r.data) return { error: r.error ?? 'No answer from the ad blocker.' };
	let lists = { '0': 'Your own rules' };
	for (let f in (ag_filtering().data?.filters ?? [])) lists['' + f.id] = f.name;
	let reason = r.data.reason ?? '';
	return { domain: d, blocked: substr(reason, 0, 8) == 'Filtered', allowed_by_rule: reason == 'NotFilteredWhiteList',
		rules: map(r.data.rules ?? [], x => ({ text: x.text, list: lists['' + x.filter_list_id] ?? 'A blocklist' })) };
};

// ---------- access keys ----------

function random_token() {
	let f = open('/dev/urandom', 'r'), raw = f.read(32);
	f.close();
	return hexenc(raw);
}

export function token_ok(tok) {
	if (type(tok) != 'string' || !match(tok, /^[0-9a-f]{64}$/)) return false;
	return (digest.sha256(tok) in load(TOKENS, {}));
};

export function mint_token(name, ip) {
	let tok = random_token();
	locked(() => {
		let all = load(TOKENS, {});
		all[digest.sha256(tok)] = { name: replace(substr(name ?? 'iPhone', 0, 40), /[^ -~]/g, '?'), created: time(), ip };
		save_private(TOKENS, all);
	});
	return tok;
};

/* Paired phones, identified by the first 12 characters of the key's hash (the keys themselves are never stored). */
export function phones(current) {
	let out = [], cur = current ? digest.sha256(current) : null;
	for (let h, v in load(TOKENS, {}))
		push(out, { id: substr(h, 0, 12), name: v.name, created: v.created, ip: v.ip, current: h == cur, notifications: !!v.apns?.token });
	return sort(out, (a, b) => b.created - a.created);
};

/* Remember where Apple delivers notifications for the phone that holds this access key. */
export function push_register(tok, b) {
	if (type(b.token) != 'string' || !match(b.token, /^[0-9a-f]{64,200}$/)) return 'That is not a notification address.';
	return locked(() => {
		let all = load(TOKENS, {}), h = digest.sha256(tok);
		if (!(h in all)) return 'unknown phone';
		all[h].apns = { token: b.token, env: b.env == 'production' ? 'production' : 'sandbox' };
		// the phone's own key: alert text is encrypted with it, so only that phone can read it
		if (type(b.key) == 'string' && match(b.key, /^[0-9a-f]{128}$/)) all[h].apns.key = b.key;
		save_private(TOKENS, all);
		return null;
	});
};

export function push_this_phone(tok) {
	let v = load(TOKENS, {})[digest.sha256(tok)];
	return { registered: !!v?.apns?.token, encrypted: !!v?.apns?.key };
};

export function push_targets() {
	let out = [];
	for (let h, v in load(TOKENS, {})) if (v.apns?.token) push(out, v.apns);
	return out;
};

export function push_forget(gone) {
	locked(() => {
		let all = load(TOKENS, {}), changed = false;
		for (let h, v in all) if (v.apns?.token && (v.apns.token in gone)) { delete v.apns; changed = true; }
		if (changed) save_private(TOKENS, all);
	});
};

export function history() {
	return load(HISTORY, []);
};

export function revoke_phone(id) {
	if (type(id) != 'string' || !match(id, /^[0-9a-f]{12}$/)) return 'unknown phone';
	return locked(() => {
		let all = load(TOKENS, {}), hit = filter(keys(all), h => substr(h, 0, 12) == id);
		if (!length(hit)) return 'unknown phone';
		add_alert('router', 'A phone was unpaired', all[hit[0]].name, 'info');
		delete all[hit[0]];
		save_private(TOKENS, all);
		return null;
	});
};

/* Pairing proves you know the router's administrator password, the same one LuCI asks for. */
export function pair(password, name, ip) {
	let fails = load(RUN + '/pairfail.json', []), now = time();
	fails = filter(fails, t => now - t < 600);
	if (length(fails) >= 5) return { code: 429, error: 'Too many wrong passwords. Try again in 10 minutes.' };
	let conn = connect();
	let ses = (type(password) == 'string' && length(password)) ? conn.call('session', 'login', { username: 'root', password, timeout: 5 }) : null;
	if (!ses?.ubus_rpc_session) {
		push(fails, now);
		save(RUN + '/pairfail.json', fails);
		return { code: 403, error: 'That is not the router\'s administrator password.' };
	}
	conn.call('session', 'destroy', { ubus_rpc_session: ses.ubus_rpc_session });
	add_alert('router', 'A phone was paired', `${substr(name ?? 'iPhone', 0, 40)} from ${ip}.`, 'warning');
	return { code: 200, token: mint_token(name, ip) };
};
