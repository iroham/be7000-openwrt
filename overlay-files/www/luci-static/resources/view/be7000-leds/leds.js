'use strict';
'require view';
'require rpc';
'require ui';

// System, LEDs: two indicator roles that the board can show but stock
// OpenWrt does not set up. The work is /usr/libexec/be7000-leds behind the
// rpcd object be7000-leds.

var callStatus = rpc.declare({ object: 'be7000-leds', method: 'status' });
var callSet = rpc.declare({ object: 'be7000-leds', method: 'set', params: [ 'what', 'on' ] });
var callAiot = rpc.declare({
	object: 'be7000-leds', method: 'aiot_set',
	params: [ 'source', 'dev', 'flags', 'service', 'target', 'cmd', 'show', 'invert', 'on_ms', 'off_ms' ]
});

var CSS = `
.bl-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px;margin:12px 0 18px}
.bl-card{padding:14px 16px;border-radius:12px;border:1px solid var(--nb-border,rgba(128,128,128,.3));background:var(--nb-surface-2,rgba(128,128,128,.05));display:flex;flex-direction:column;gap:8px}
.bl-card.on{border-color:var(--nb-accent,#4f46e5);box-shadow:0 0 0 3px var(--nb-accent-ring,rgba(79,70,229,.18))}
.bl-card h4{margin:0;font-size:15px;display:flex;flex-wrap:wrap;align-items:center;gap:8px}
.bl-badge{font-size:11px;font-weight:600;padding:1px 8px;border-radius:999px;background:var(--nb-accent,#4f46e5);color:var(--nb-on-accent,#fff)}
.bl-badge.soft{background:var(--nb-surface-3,rgba(128,128,128,.18));color:var(--nb-text,inherit)}
.bl-text{font-size:13px}
.bl-note{font-size:12px;color:var(--nb-muted,#888)}
.bl-act{margin-top:auto;display:flex;flex-wrap:wrap;gap:8px}
.bl-form{display:grid;grid-template-columns:minmax(120px,max-content) 1fr;gap:8px 12px;align-items:center;margin-top:6px}
.bl-form label{font-size:13px}
.bl-form .cbi-input-text,.bl-form select{width:100%;max-width:420px}
.bl-form .bl-flags{display:flex;flex-wrap:wrap;gap:12px}
.bl-about{max-width:860px;margin-top:8px}
.bl-about h3{margin:18px 0 6px}
.bl-sec{margin:0 0 14px}
.bl-sec h4{margin:12px 0 4px;font-size:14px}
.bl-sec p,.bl-sec li{font-size:13px;line-height:1.5}
.bl-sec ul{margin:4px 0 8px 18px;padding:0}
.bl-sec pre{font-size:12.5px;padding:8px 10px;border-radius:8px;background:var(--nb-surface-2,rgba(128,128,128,.08));overflow-x:auto;white-space:pre}
`;

return view.extend({
	load: function() {
		return L.resolveDefault(callStatus(), {});
	},

	toggle: function(what, on) {
		return callSet(what, on).then(function(r) {
			if (!r || !r.ok) {
				ui.addNotification(null, E('p', (r && r.output) || _('Не удалось применить')), 'danger');
				return;
			}
			window.location.reload();
		});
	},

	card: function(on, title, badges, text, note, what, disabled) {
		return E('div', { 'class': 'bl-card' + (on ? ' on' : '') }, [
			E('h4', {}, [ title ].concat(badges)),
			E('div', { 'class': 'bl-text' }, text),
			note ? E('div', { 'class': 'bl-note' }, note) : '',
			E('div', { 'class': 'bl-act' }, [
				E('button', {
					'class': on ? 'cbi-button cbi-button-neutral' : 'cbi-button cbi-button-action important',
					'disabled': disabled ? true : null,
					'click': ui.createHandlerFn(this, 'toggle', what, !on)
				}, on ? _('Выключить') : _('Включить'))
			])
		]);
	},

	render: function(st) {
		var head = [
			E('style', {}, CSS),
			E('h2', {}, _('Светодиоды')),
			E('div', { 'class': 'cbi-map-descr' },
				_('На передней панели два индикатора, которым в Beam WRT можно дать дополнительные роли. Оба включены по умолчанию, здесь их можно выключить. Всё применяется сразу.'))
		];

		if (st.error)
			return E([], head.concat([ E('p', {}, st.error) ]));

		var w2 = this.card(st.wlan2g, _('Wi-Fi 2,4 ГГц, янтарный'),
			st.wlan2g_active ? [ E('span', { 'class': 'bl-badge' }, _('включено')) ] :
				(st.wlan2g_busy ? [ E('span', { 'class': 'bl-badge soft' }, _('занят')) ] : []),
			_('Янтарный светодиод индикатора сети мигает, когда по Wi-Fi 2,4 ГГц идёт трафик. Белый светодиод рядом остаётся индикатором 5 ГГц, так что по цвету видно, какой диапазон работает.'),
			st.wlan2g_busy ? _('Этот светодиод уже настроен вами на странице Индикаторы, поэтому он не тронут.') : _('Применяется сразу.'),
			'wlan2g', st.wlan2g_busy);

		var ai = this.aiotCard(st);

		return E([], head.concat([ E('div', { 'class': 'bl-cards' }, [ w2, ai ]), this.about() ]));
	},

	aiotCard: function(st) {
		var self = this;
		var SRC = [
			[ 'hf', _('Работу Hybrid Failover') ],
			[ 'netdev', _('Связь или трафик интерфейса') ],
			[ 'service', _('Работу процесса') ],
			[ 'internet', _('Доступность интернета') ],
			[ 'command', _('Результат своей команды') ],
			[ 'on', _('Горит всегда') ],
			[ 'timer', _('Мигает всегда') ],
			[ 'heartbeat', _('Пульс') ],
			[ 'off', _('Выключен') ]
		];
		var POLLED = { hf: 1, service: 1, internet: 1, command: 1 };

		var sel = E('select', { 'class': 'cbi-input-select' }, SRC.map(function(o) {
			return E('option', { 'value': o[0], 'selected': o[0] == st.source ? true : null }, o[1]);
		}));
		var dev = E('select', { 'class': 'cbi-input-select' }, (st.ifaces || []).map(function(n) {
			return E('option', { 'value': n, 'selected': n == st.dev ? true : null }, n);
		}));
		var flag = function(name, label) {
			return E('label', {}, [ E('input', { 'type': 'checkbox', 'data-flag': name, 'checked': (st.flags || '').split(' ').indexOf(name) >= 0 ? true : null }), ' ', label ]);
		};
		var flags = E('div', { 'class': 'bl-flags' }, [ flag('link', _('связь')), flag('rx', _('приём')), flag('tx', _('передача')) ]);
		var service = E('input', { 'class': 'cbi-input-text', 'type': 'text', 'value': st.service || '', 'placeholder': 'sing-box' });
		var target = E('input', { 'class': 'cbi-input-text', 'type': 'text', 'value': st.target || '1.1.1.1' });
		var cmd = E('input', { 'class': 'cbi-input-text', 'type': 'text', 'value': st.cmd || '', 'placeholder': 'ip link show awg0' });
		var show = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'on', 'selected': st.show != 'blink' ? true : null }, _('горит')),
			E('option', { 'value': 'blink', 'selected': st.show == 'blink' ? true : null }, _('мигает'))
		]);
		var inv = E('input', { 'type': 'checkbox', 'checked': st.invert ? true : null });
		var onms = E('input', { 'class': 'cbi-input-text', 'type': 'number', 'min': 50, 'max': 10000, 'value': st.on_ms || 500, 'style': 'max-width:120px' });
		var offms = E('input', { 'class': 'cbi-input-text', 'type': 'number', 'min': 50, 'max': 10000, 'value': st.off_ms || 500, 'style': 'max-width:120px' });

		var rows = {
			dev: [ E('label', {}, _('Интерфейс')), dev ],
			flags: [ E('label', {}, _('Что считать')), flags ],
			service: [ E('label', {}, _('Имя процесса')), service ],
			target: [ E('label', {}, _('Адрес для проверки')), target ],
			cmd: [ E('label', {}, _('Команда')), cmd ],
			show: [ E('label', {}, _('Когда выполнено')), show ],
			inv: [ E('label', {}, _('Наоборот')), E('label', {}, [ inv, ' ', _('светодиод показывает, что условие не выполнено') ]) ],
			ms: [ E('label', {}, _('Мигание, мс')), E('div', {}, [ onms, ' ', _('горит'), ' ', offms, ' ', _('не горит') ]) ]
		};
		var form = E('div', { 'class': 'bl-form' });
		var order = [ 'dev', 'flags', 'service', 'target', 'cmd', 'show', 'inv', 'ms' ];
		order.forEach(function(k) { rows[k].forEach(function(n) { n.setAttribute && n.setAttribute('data-row', k); form.appendChild(n); }); });

		var refresh = function() {
			var src = sel.value, polled = !!POLLED[src], blinkMs = (src == 'timer') || (polled && show.value == 'blink');
			var vis = { dev: src == 'netdev', flags: src == 'netdev', service: src == 'service', target: src == 'internet', cmd: src == 'command', show: polled, inv: polled, ms: blinkMs };
			order.forEach(function(k) {
				form.querySelectorAll('[data-row="' + k + '"]').forEach(function(n) { n.style.display = vis[k] ? '' : 'none'; });
			});
		};
		sel.addEventListener('change', refresh);
		show.addEventListener('change', refresh);
		refresh();

		var save = function() {
			var fl = [];
			flags.querySelectorAll('input[data-flag]').forEach(function(i) { if (i.checked) fl.push(i.getAttribute('data-flag')); });
			return callAiot(sel.value, dev.value, fl.join(' '), service.value.trim(), target.value.trim(), cmd.value.trim(),
				show.value, inv.checked, +onms.value || 500, +offms.value || 500).then(function(r) {
				if (!r || !r.ok) {
					ui.addNotification(null, E('p', (r && r.output) || _('Не удалось применить')), 'danger');
					return;
				}
				window.location.reload();
			});
		};

		var busy = st.aiot_busy;
		return E('div', { 'class': 'bl-card' + (st.source != 'off' ? ' on' : '') }, [
			E('h4', {}, [ _('Светодиод AIoT, белый'),
				st.aiot_on ? E('span', { 'class': 'bl-badge' }, _('горит')) : E('span', { 'class': 'bl-badge soft' }, _('не горит')),
				busy ? E('span', { 'class': 'bl-badge soft' }, _('занят')) : '' ]),
			E('div', { 'class': 'bl-text' },
				_('Этот светодиод можно привязать к чему угодно. Выберите, что он показывает, и как. По умолчанию он горит, пока работает Hybrid Failover.')),
			busy ? E('div', { 'class': 'bl-note' }, _('Этот светодиод уже настроен вами на странице Индикаторы, поэтому он не тронут.')) : '',
			E('div', { 'class': 'bl-form' }, [ E('label', {}, _('Что показывает')), sel ]),
			form,
			E('div', { 'class': 'bl-act' }, [
				E('button', { 'class': 'cbi-button cbi-button-action important', 'disabled': busy ? true : null,
					'click': ui.createHandlerFn(this, save) }, _('Сохранить'))
			])
		]);
	},

	about: function() {
		var sec = function(title, paras) {
			return E('div', { 'class': 'bl-sec' }, [ E('h4', {}, title) ].concat(paras.map(function(p) {
				return Array.isArray(p)
					? E('ul', {}, p.map(function(li) { return E('li', {}, li); }))
					: E('p', {}, p);
			})));
		};

		return E('div', { 'class': 'bl-about' }, [
			E('h3', {}, _('Как это устроено')),
			sec(_('Какие светодиоды есть'), [
				_('На плате есть белые и янтарные светодиоды. Яркость у них не регулируется, они либо горят, либо нет. Белый светодиод сети по умолчанию показывает трафик Wi-Fi 5 ГГц, белый системный горит, когда роутер загрузился. Янтарный системный показывает проблемы при загрузке.'),
				_('Светодиоды LAN и WAN у разъёмов показывают связь и трафик порта.')
			]),
			sec(_('Wi-Fi 2,4 ГГц'), [
				_('Янтарный светодиод сети привязывается к интерфейсу точки доступа 2,4 ГГц и мигает при приёме и передаче. В режиме MLO белый светодиод следует за общим интерфейсом MLO, это делается само при переключении режима 5 ГГц.')
			]),
			sec(_('Светодиод AIoT'), [
				_('Белый светодиод AIoT свободен, ему можно дать любую роль. Источники, которые можно выбрать'),
				[ _('Работа Hybrid Failover. Процесс запущен и таблица его правил в межсетевом экране на месте. Проверка каждые пять секунд.'),
				  _('Связь или трафик интерфейса. Светодиод сам следует за интерфейсом, мигает при приёме и передаче или горит, пока есть связь. Подходит любой интерфейс, например wan, awg0 или br-lan.'),
				  _('Работа процесса. Горит, пока в системе есть процесс с таким именем.'),
				  _('Доступность интернета. Роутер раз в 15 секунд проверяет адрес командой ping.'),
				  _('Результат своей команды. Команда выполняется раз в пять секунд от имени root, светодиод показывает, завершилась ли она с кодом 0.'),
				  _('Горит всегда, мигает всегда, пульс или выключен.') ],
				_('Для проверяемых источников можно выбрать, как показывать выполненное условие, горением или миганием, и перевернуть логику: тогда светодиод покажет, что условие не выполнено. Это удобно для сигнала о неполадке.')
			]),
			sec(_('Если светодиод уже настроен вами'), [
				_('Если вы сами назначили янтарный светодиод сети или белый AIoT на странице Индикаторы, Beam WRT их не трогает. Чтобы вернуть управление сюда, удалите свою настройку на той странице.')
			]),
			sec(_('Из консоли'), [
				E('pre', {}, '/usr/libexec/be7000-leds status\n/usr/libexec/be7000-leds wlan2g off\n/usr/libexec/be7000-leds aiot off')
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
