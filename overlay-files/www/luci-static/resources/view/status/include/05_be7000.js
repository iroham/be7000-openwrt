'use strict';
'require baseclass';
'require rpc';

// Project card at the top of Status, Overview: build version and links to
// the repository, releases, this version's notes, the privacy text and the build's own pages.

var REPO = 'https://github.com/iroham/be7000-openwrt';

var callSystemBoard = rpc.declare({ object: 'system', method: 'board' });

// the MiWRT mark, same as the theme's logo.svg
var LOGO = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64"> <rect width="64" height="64" rx="15" fill="#4b3bff"/> <g fill="none" stroke="#fff" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"> <path d="M14.5 43V31.8L25.5 22.4l9.6 11.3c1.9 2.2 5 2.5 6.9.7 1.8-1.7 1.7-4.6-.3-6.1-1.5-1.1-3.5-.9-4.6.4"/> <path d="M38.9 21.2a9.6 9.6 0 0 1 9.4 9.9"/> <path d="M38.6 15.6a15.2 15.2 0 0 1 15.3 15.8"/> </g> </svg>';

var TEXT = {
	ru: {
		sub: 'Прошивка и приложение для телефона для Xiaomi BE7000 на базе OpenWrt, ядро 6.18',
		version: 'Версия',
		github: 'Исходники на GitHub',
		releases: 'Релизы',
		notes: 'Что нового',
		privacy: 'Конфиденциальность',
		issues: 'Сообщить об ошибке',
		update: 'Обновление сборки',
		credits: 'Благодарности'
	},
	en: {
		sub: 'Firmware and phone app for the Xiaomi BE7000, based on OpenWrt, kernel 6.18',
		version: 'Version',
		github: 'Sources on GitHub',
		releases: 'Releases',
		notes: 'What\'s new',
		privacy: 'Privacy',
		issues: 'Report a problem',
		update: 'Build update',
		credits: 'Credits'
	},
	zh: {
		sub: '基于 OpenWrt 的小米 BE7000 固件与手机应用，内核 6.18',
		version: '版本',
		github: 'GitHub 上的源代码',
		releases: '发布版本',
		notes: '更新内容',
		privacy: '隐私',
		issues: '报告问题',
		update: '固件更新',
		credits: '致谢'
	}
};

function lang() {
	var l = document.documentElement.lang || '';
	return /^zh/i.test(l) ? 'zh' : /^en/i.test(l) ? 'en' : 'ru';
}

var ICONS = {
	code: 'M8 6l-6 6 6 6M16 6l6 6-6 6',
	tag: 'M3 12V4h8l10 10-8 8L3 12zM7.5 8.5h.01',
	notes: 'M6 3h9l4 4v14H6zM14 3v5h5M9 12h7M9 16h7',
	lock: 'M6 11h12v9H6zM9 11V8a3 3 0 0 1 6 0v3',
	bug: 'M12 3v2M5 8l2 1M19 8l-2 1M4 14h3M17 14h3M5 20l2-2M19 20l-2-2M8 10a4 4 0 0 1 8 0v5a4 4 0 0 1-8 0v-5z',
	update: 'M4 12a8 8 0 0 1 14-5.3M20 4v5h-5M20 12a8 8 0 0 1-14 5.3M4 20v-5h5',
	heart: 'M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z'
};

var CSS = `
.be7k-card{display:flex;flex-wrap:wrap;align-items:center;gap:14px 20px;padding:4px 2px 2px}
.be7k-logo{flex:none;width:48px;height:48px}
.be7k-logo svg{width:48px;height:48px;display:block;border-radius:12px}
.be7k-head{flex:1 1 220px;min-width:0}
.be7k-name{font-size:17px;font-weight:650;letter-spacing:-.01em;color:var(--nb-text,inherit);text-decoration:none}
.be7k-name:hover{text-decoration:underline}
.be7k-sub{margin-top:2px;font-size:13px;color:var(--nb-text-2,inherit);opacity:.9}
.be7k-ver{display:inline-block;margin-top:8px;padding:2px 9px;border-radius:999px;font:12px/1.6 var(--font-mono,ui-monospace,Menlo,Consolas,monospace);
	background:var(--nb-accent-soft,rgba(79,70,229,.09));color:var(--nb-accent-strong,var(--nb-accent,#4f46e5))}
.be7k-links{flex:1 1 360px;display:flex;flex-wrap:wrap;gap:8px;justify-content:flex-end}
.be7k-links a{display:inline-flex;align-items:center;gap:7px;padding:7px 12px;border-radius:9px;font-size:13px;line-height:1.2;white-space:nowrap;
	text-decoration:none;color:var(--nb-text,inherit);background:var(--nb-surface-2,rgba(128,128,128,.08));
	border:1px solid var(--nb-border,rgba(128,128,128,.25));transition:border-color .15s,background .15s,color .15s}
.be7k-links a:hover{border-color:var(--nb-accent,#4f46e5);color:var(--nb-accent,#4f46e5);background:var(--nb-accent-soft,rgba(79,70,229,.09))}
.be7k-links a.be7k-main{background:var(--nb-accent,#4f46e5);border-color:var(--nb-accent,#4f46e5);color:var(--nb-on-accent,#fff)}
.be7k-links a.be7k-main:hover{background:var(--nb-accent-strong,#4338ca);color:var(--nb-on-accent,#fff)}
.be7k-links svg{width:15px;height:15px;flex:none}
@media (max-width:640px){.be7k-links{justify-content:flex-start}}
`;

function icon(name) {
	var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
	var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
	svg.setAttribute('viewBox', '0 0 24 24');
	svg.setAttribute('fill', 'none');
	svg.setAttribute('stroke', 'currentColor');
	svg.setAttribute('stroke-width', '2');
	svg.setAttribute('stroke-linecap', 'round');
	svg.setAttribute('stroke-linejoin', 'round');
	svg.setAttribute('aria-hidden', 'true');
	path.setAttribute('d', ICONS[name]);
	svg.appendChild(path);
	return svg;
}

// every link opens in a new tab, the build's own pages too
function link(href, name, text, cls) {
	return E('a', {
		'href': href,
		'class': cls || '',
		'target': '_blank',
		'rel': 'noopener'
	}, [ icon(name), text ]);
}

return baseclass.extend({
	title: { ru: 'Проект', en: 'Project', zh: '项目' }[lang()],

	load: function() {
		return L.resolveDefault(callSystemBoard(), {});
	},

	render: function(board) {
		var tx = TEXT[lang()];
		var ver = (L.isObject(board.release) ? board.release.version : '') || '';

		ver = ver.replace(/^(BE7000|Beam WRT|MiWRT)\s+/, '');

		if (!document.getElementById('be7k-css'))
			document.head.appendChild(E('style', { 'id': 'be7k-css' }, CSS));

		var card = E('div', { 'class': 'be7k-card' }, [
			E('div', { 'class': 'be7k-logo', 'aria-hidden': 'true' }),
			E('div', { 'class': 'be7k-head' }, [
				E('a', { 'class': 'be7k-name', 'href': REPO, 'target': '_blank', 'rel': 'noopener' }, 'MiWRT'),
				E('div', { 'class': 'be7k-sub' }, tx.sub),
				ver ? E('span', { 'class': 'be7k-ver' }, tx.version + ' ' + ver) : ''
			]),
			E('div', { 'class': 'be7k-links' }, [
				link(REPO, 'code', tx.github, 'be7k-main'),
				link(REPO + '/releases', 'tag', tx.releases),
				link(REPO + '/blob/miwrt/docs/release-notes/v' + ver.replace(/\s.*$/, '') + '.md', 'notes', tx.notes),
				link(REPO + '/issues', 'bug', tx.issues),
				link(REPO + '/blob/miwrt/PRIVACY.md', 'lock', tx.privacy),
				link(L.url('admin/system/be7000-update'), 'update', tx.update),
				link(L.url('admin/system/credits'), 'heart', tx.credits)
			])
		]);

		card.querySelector('.be7k-logo').innerHTML = LOGO;

		return card;
	}
});
