'use strict';
'require view';
'require request';
'require fs';

// Names, links and texts live in be7000-credits/credits.json, the SSH
// banner is built from the same file (/usr/libexec/be7000-banner).

var CSS = `
.bc{--bc-bg:#fff;--bc-fg:#1f2430;--bc-mute:#6b7280;--bc-line:rgba(0,0,0,.08);--bc-card:#fff;--bc-glow:rgba(255,106,0,.18);
	max-width:1100px;margin:0 auto 32px;color:var(--bc-fg);font-size:14px;line-height:1.5}
.bc.dark{--bc-fg:#e7e9ee;--bc-mute:#9aa3b2;--bc-line:rgba(255,255,255,.1);--bc-card:rgba(255,255,255,.04);--bc-glow:rgba(255,140,60,.22)}
.bc-hero{position:relative;overflow:hidden;border-radius:18px;padding:34px 32px 30px;margin:8px 0 28px;color:#fff;
	background:radial-gradient(120% 140% at 0% 0%,#ff8a3d 0%,#f0561f 38%,#7a2bd9 100%);box-shadow:0 18px 40px -18px rgba(122,43,217,.55)}
.bc-hero:after{content:"";position:absolute;right:-60px;top:-60px;width:260px;height:260px;border-radius:50%;background:rgba(255,255,255,.12)}
.bc-hero h2{margin:0 0 8px;font-size:30px;font-weight:700;letter-spacing:-.02em;color:#fff;border:0;padding:0}
.bc-hero p{margin:0;max-width:720px;font-size:15px;opacity:.93}
.bc-hero .bc-ver{display:inline-block;margin-top:16px;padding:4px 12px;border-radius:999px;background:rgba(255,255,255,.18);font-size:12px;font-weight:600;letter-spacing:.02em}
.bc-sec{margin:26px 0 12px;display:flex;align-items:center;gap:10px;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:var(--bc-mute)}
.bc-sec:after{content:"";flex:1;height:1px;background:var(--bc-line)}
.bc-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}
.bc-card{display:flex;gap:14px;padding:16px 18px;border-radius:14px;background:var(--bc-card);border:1px solid var(--bc-line);
	text-decoration:none!important;color:inherit!important;transition:transform .15s ease,box-shadow .15s ease,border-color .15s ease}
.bc-card:hover{transform:translateY(-2px);box-shadow:0 12px 28px -14px var(--bc-glow);border-color:rgba(240,86,31,.45)}
.bc-card.star{grid-column:1/-1;background:linear-gradient(135deg,rgba(255,138,61,.12),rgba(122,43,217,.10));border-color:rgba(240,86,31,.35)}
.bc-av{flex:0 0 46px;height:46px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:#fff;font-weight:700;font-size:17px;letter-spacing:.02em}
.bc-card.star .bc-av{flex-basis:58px;height:58px;font-size:21px}
.bc-body{min-width:0}
.bc-name{display:flex;align-items:center;flex-wrap:wrap;gap:8px;font-weight:700;font-size:15px}
.bc-card.star .bc-name{font-size:18px}
.bc-tag{font-size:11px;font-weight:600;padding:1px 8px;border-radius:999px;border:1px solid var(--bc-line);color:var(--bc-mute)}
.bc-heart{font-size:11px;font-weight:700;padding:1px 8px;border-radius:999px;background:#f0561f;color:#fff}
.bc-what{margin-top:4px;color:var(--bc-mute)}
.bc-card.star .bc-what{color:inherit;opacity:.85;font-size:14.5px}
.bc-foot{margin-top:30px;text-align:center;color:var(--bc-mute);font-size:13px}
.bc-foot a{color:#f0561f}
`;

var PALETTE = ['#f0561f', '#7a2bd9', '#0ea5a4', '#2563eb', '#db2777', '#16a34a', '#d97706', '#4f46e5'];

function color(name) {
	var h = 0;
	for (var i = 0; i < name.length; i++)
		h = (h * 31 + name.charCodeAt(i)) >>> 0;
	return PALETTE[h % PALETTE.length];
}

function initials(name) {
	var w = name.replace(/[^A-Za-zА-Яа-я0-9 ]/g, ' ').trim().split(/\s+/);
	return (w.length > 1 ? w[0][0] + w[1][0] : name.replace(/[^A-Za-zА-Яа-я]/g, '').slice(0, 2)).toUpperCase();
}

function isDark() {
	var c = window.getComputedStyle(document.body).backgroundColor.match(/\d+/g);
	if (!c)
		return false;
	return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) < 128;
}

return view.extend({
	load: function() {
		return Promise.all([
			request.get(L.resource('be7000-credits/credits.json')).then(function(r) { return r.json(); }),
			L.resolveDefault(fs.read('/etc/be7000-release'), '')
		]);
	},

	render: function(data) {
		var d = data[0];
		var ver = (String(data[1]).match(/^VERSION=(.+)$/m) || [])[1];
		var ru = !/^en/i.test(document.documentElement.lang || navigator.language || 'ru');
		var t = function(o) { return o[ru ? 'ru' : 'en']; };

		var root = E('div', { 'class': 'bc' + (isDark() ? ' dark' : '') }, [
			E('style', {}, CSS),
			E('div', { 'class': 'bc-hero' }, [
				E('h2', {}, ru ? 'Спасибо' : 'Thank you'),
				E('p', {}, ru
					? 'Эта сборка появилась благодаря людям, которые проверяли её на своих роутерах, присылали логи, давали доступ к платам и делали работу, на которой она стоит.'
					: 'This build exists thanks to the people who tested it on their routers, sent logs, gave access to their boards and did the work it stands on.'),
				E('span', { 'class': 'bc-ver' }, 'be7000-openwrt' + (ver ? ' ' + ver : ''))
			])
		]);

		d.groups.forEach(function(g) {
			root.appendChild(E('div', { 'class': 'bc-sec' }, t(g.title)));
			root.appendChild(E('div', { 'class': 'bc-grid' }, g.people.map(function(p) {
				return E('a', { 'class': 'bc-card' + (p.star ? ' star' : ''), 'href': p.url, 'target': '_blank', 'rel': 'noopener' }, [
					E('div', { 'class': 'bc-av', 'style': 'background:' + color(p.name) }, initials(p.name)),
					E('div', { 'class': 'bc-body' }, [
						E('div', { 'class': 'bc-name' }, [
							p.name,
							E('span', { 'class': 'bc-tag' }, p.site),
							p.star ? E('span', { 'class': 'bc-heart' }, ru ? 'нашли причину на его плате' : 'the fix was found on his board') : ''
						]),
						E('div', { 'class': 'bc-what' }, t(p))
					])
				]);
			})));
		});

		root.appendChild(E('div', { 'class': 'bc-foot' }, [
			ru ? 'Исходники, релизы и обсуждение: ' : 'Sources, releases and discussion: ',
			E('a', { 'href': d.project, 'target': '_blank', 'rel': 'noopener' }, d.project.replace('https://', ''))
		]));

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
