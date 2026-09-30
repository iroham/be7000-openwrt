'use strict';
'require view';
'require rpc';
'require ui';

// System, Slots: the two firmware slots, which one runs, which one boots,
// what the other one holds, and a switch. The work is
// /usr/libexec/be7000-slots behind the rpcd object be7000-slots.

var callStatus = rpc.declare({ object: 'be7000-slots', method: 'status' });
var callInfo = rpc.declare({ object: 'be7000-slots', method: 'info', params: [ 'slot' ] });
var callSwitch = rpc.declare({ object: 'be7000-slots', method: 'switch', params: [ 'slot', 'reboot' ] });

var CSS = `
.bs-slots{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px;margin:12px 0 18px}
.bs-slot{padding:14px 16px;border-radius:12px;border:1px solid var(--nb-border,rgba(128,128,128,.3));background:var(--nb-surface-2,rgba(128,128,128,.05));display:flex;flex-direction:column;gap:8px}
.bs-slot.run{border-color:var(--nb-accent,#4f46e5);box-shadow:0 0 0 3px var(--nb-accent-ring,rgba(79,70,229,.18))}
.bs-slot h4{margin:0;font-size:15px;display:flex;flex-wrap:wrap;align-items:center;gap:8px}
.bs-badge{font-size:11px;font-weight:600;padding:1px 8px;border-radius:999px;background:var(--nb-accent,#4f46e5);color:var(--nb-on-accent,#fff)}
.bs-badge.soft{background:var(--nb-surface-3,rgba(128,128,128,.18));color:var(--nb-text,inherit)}
.bs-what{font-size:13px}
.bs-mtd{font-size:12px;color:var(--nb-muted,#888)}
.bs-act{margin-top:auto;display:flex;flex-wrap:wrap;gap:8px}
.bs-flags td{font-family:var(--font-mono,ui-monospace,Menlo,monospace);font-size:12.5px}
`;

var KIND = {
	stock: function() { return _('Заводская прошивка Xiaomi'); },
	openwrt: function() { return _('Beam WRT или другой OpenWrt'); },
	test: function() { return _('Тестовая сборка Beam WRT'); },
	empty: function() { return _('Пусто'); },
	unknown: function() { return _('Не удалось определить'); }
};

return view.extend({
	load: function() {
		return L.resolveDefault(callStatus(), {});
	},

	slotCard: function(st, slot) {
		var run = (st.current == slot);
		var boots = (String(st.last_success) == String(slot));
		var what = E('div', { 'class': 'bs-what' }, run ? (st['this'] || '') : _('Содержимое не проверялось.'));
		var act = E('div', { 'class': 'bs-act' });

		if (!run) {
			act.appendChild(E('button', {
				'class': 'cbi-button cbi-button-neutral',
				'click': ui.createHandlerFn(this, 'look', slot, what, act)
			}, _('Посмотреть, что там')));
		}

		return E('div', { 'class': 'bs-slot' + (run ? ' run' : '') }, [
			E('h4', {}, [
				_('Слот %d').format(slot),
				run ? E('span', { 'class': 'bs-badge' }, _('работает сейчас')) : '',
				boots ? E('span', { 'class': 'bs-badge soft' }, _('загружается по умолчанию')) : ''
			]),
			E('div', { 'class': 'bs-mtd' }, slot == 0 ? 'mtd rootfs' : 'mtd rootfs_1'),
			what,
			act
		]);
	},

	look: function(slot, what, act) {
		return L.resolveDefault(callInfo(slot), {}).then(L.bind(function(r) {
			if (r.error) {
				L.dom.content(what, r.error);
				return;
			}
			var k = (KIND[r.kind] || KIND.unknown)();
			L.dom.content(what, r.version ? '%s: %s'.format(k, r.version) : k);
			L.dom.content(act, '');
			if (r.kind == 'stock' || r.kind == 'openwrt' || r.kind == 'test')
				act.appendChild(E('button', {
					'class': 'cbi-button cbi-button-action important',
					'click': ui.createHandlerFn(this, 'confirm', slot, r)
				}, _('Сделать основным и перезагрузить')));
		}, this));
	},

	confirm: function(slot, info) {
		var back;
		if (info.kind == 'stock')
			back = [
				E('p', {}, _('Роутер загрузит заводскую прошивку, и она сама станет основной. Настройки Beam WRT останутся на месте.')),
				E('p', {}, _('Вернуться на Beam WRT из стока можно так. Если в стоке включён SSH, выполните')),
				E('pre', {}, 'nvram set flag_last_success=%d\nnvram set flag_boot_rootfs=%d\nnvram set flag_ota_reboot=0\nnvram commit\nreboot'.format(1 - slot, 1 - slot)),
				E('p', {}, _('Или поставьте Beam WRT заново скриптом из архива релиза, настройки сохранятся.'))
			];
		else
			back = [
				E('p', {}, _('Роутер загрузит %s из слота %d, и эта прошивка станет основной.').format(info.version || _('прошивку'), slot)),
				E('p', {}, _('Вернуться можно на этой же странице той прошивки.'))
			];

		ui.showModal(_('Сделать слот %d основным?').format(slot), back.concat([
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, _('Отмена')),
				' ',
				E('button', { 'class': 'cbi-button cbi-button-negative important', 'click': L.bind(function() {
					ui.showModal(_('Переключаю слот'), [ E('p', { 'class': 'spinning' }, _('Переключаю слот')) ]);
					return L.resolveDefault(callSwitch(slot, true), {}).then(function(r) {
						if (!r.ok) {
							ui.showModal(_('Не получилось'), [ E('pre', {}, r.output || '-'),
								E('div', { 'class': 'right' }, E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, _('Закрыть'))) ]);
							return;
						}
						ui.showModal(_('Перезагрузка'), [ E('p', { 'class': 'spinning' },
							_('Роутер перезагружается в слот %d. Эта страница больше не ответит.').format(slot)) ]);
					});
				}, this) }, _('Переключить и перезагрузить'))
			])
		]));
	},

	render: function(st) {
		if (!document.getElementById('bs-css'))
			document.head.appendChild(E('style', { 'id': 'bs-css' }, CSS));

		if (st.error || st.current == null || st.current < 0)
			return E('div', { 'class': 'cbi-map' }, [
				E('h2', {}, _('Слоты')),
				E('p', { 'class': 'alert-message warning' }, st.error || _('Не удалось определить текущий слот.'))
			]);

		var flags = [
			[ 'flag_last_success', st.last_success ],
			[ 'flag_ota_reboot', st.ota_reboot ],
			[ 'flag_boot_success', st.boot_success ],
			[ 'flag_try_sys1_failed', st.try_sys1_failed ],
			[ 'flag_try_sys2_failed', st.try_sys2_failed ],
			[ 'flag_format_overlay', st.format_overlay || '-' ]
		];

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Слоты')),
			E('div', { 'class': 'cbi-map-descr' }, _('На флеше два слота для прошивки. Загрузчик запускает один из них, второй ждёт: обычно там заводская прошивка, и на неё можно вернуться в любой момент. Прошивка, которая загрузилась, сама делает свой слот основным.')),
			E('div', { 'class': 'bs-slots' }, [ this.slotCard(st, 0), this.slotCard(st, 1) ]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Флаги загрузчика')),
				E('table', { 'class': 'table bs-flags' }, flags.map(function(f) {
					return E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '40%' }, f[0]), E('td', { 'class': 'td left' }, String(f[1] ?? '-')) ]);
				}))
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
