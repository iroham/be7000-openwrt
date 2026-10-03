'use strict';
'require view';
'require rpc';
'require ui';

// System, LEDs: roles that follow a state, which the stock LED page cannot
// do. What the kernel can do by itself is set on the stock page System,
// Indicators. The work is /usr/libexec/be7000-leds behind the rpcd object
// be7000-leds.

var callStatus = rpc.declare({ object: 'be7000-leds', method: 'status' });
var callAiot = rpc.declare({
	object: 'be7000-leds', method: 'aiot_set',
	params: [ 'source', 'service', 'target', 'cmd', 'show', 'invert', 'on_ms', 'off_ms' ]
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

	aiotCard: function(st) {
		var SRC = [
			[ 'hf', _('Работу Hybrid Failover') ],
			[ 'service', _('Работу процесса') ],
			[ 'internet', _('Доступность интернета') ],
			[ 'command', _('Результат своей команды') ],
			[ 'off', _('Не управляется здесь') ]
		];
		var busy = st.aiot_busy;

		var sel = E('select', { 'class': 'cbi-input-select' }, SRC.map(function(o) {
			return E('option', { 'value': o[0], 'selected': o[0] == st.source ? true : null }, o[1]);
		}));
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
			service: [ E('label', {}, _('Имя процесса')), service ],
			target: [ E('label', {}, _('Адрес для проверки')), target ],
			cmd: [ E('label', {}, _('Команда')), cmd ],
			show: [ E('label', {}, _('Когда выполнено')), show ],
			inv: [ E('label', {}, _('Наоборот')), E('label', {}, [ inv, ' ', _('светодиод показывает, что условие не выполнено') ]) ],
			ms: [ E('label', {}, _('Мигание, мс')), E('div', {}, [ onms, ' ', _('горит'), ' ', offms, ' ', _('не горит') ]) ]
		};
		var order = [ 'service', 'target', 'cmd', 'show', 'inv', 'ms' ];
		var form = E('div', { 'class': 'bl-form' });
		order.forEach(function(k) { rows[k].forEach(function(n) { n.setAttribute('data-row', k); form.appendChild(n); }); });

		var refresh = function() {
			var src = sel.value, checked = src != 'off';
			var vis = { service: src == 'service', target: src == 'internet', cmd: src == 'command', show: checked, inv: checked, ms: checked && show.value == 'blink' };
			order.forEach(function(k) {
				form.querySelectorAll('[data-row="' + k + '"]').forEach(function(n) { n.style.display = vis[k] ? '' : 'none'; });
			});
		};
		sel.addEventListener('change', refresh);
		show.addEventListener('change', refresh);
		refresh();

		var save = function() {
			return callAiot(sel.value, service.value.trim(), target.value.trim(), cmd.value.trim(),
				show.value, inv.checked, +onms.value || 500, +offms.value || 500).then(function(r) {
				if (!r || !r.ok) {
					ui.addNotification(null, E('p', (r && r.output) || _('Не удалось применить')), 'danger');
					return;
				}
				window.location.reload();
			});
		};

		return E('div', { 'class': 'bl-card' + (st.source != 'off' && !busy ? ' on' : '') }, [
			E('h4', {}, [ _('Светодиод AIoT, белый'),
				st.aiot_on ? E('span', { 'class': 'bl-badge' }, _('горит')) : E('span', { 'class': 'bl-badge soft' }, _('не горит')),
				busy ? E('span', { 'class': 'bl-badge soft' }, _('занят')) : '' ]),
			E('div', { 'class': 'bl-text' },
				_('Светодиод показывает, выполнено ли условие. Выберите условие и то, как оно будет выглядеть. По умолчанию он горит, пока работает Hybrid Failover.')),
			busy ? E('div', { 'class': 'bl-note' }, [ _('Этот светодиод настроен на странице Индикаторы, поэтому здесь он не управляется. Удалите его настройку там, чтобы вернуть управление сюда.'), ' ',
				E('a', { 'href': L.url('admin/system/leds') }, _('Открыть Индикаторы')) ]) : '',
			E('div', { 'class': 'bl-form' }, [ E('label', {}, _('Что показывает')), sel ]),
			form,
			E('div', { 'class': 'bl-act' }, [
				E('button', { 'class': 'cbi-button cbi-button-action important', 'disabled': busy ? true : null,
					'click': ui.createHandlerFn(this, save) }, _('Сохранить'))
			])
		]);
	},

	render: function(st) {
		var head = [
			E('style', {}, CSS),
			E('h2', {}, _('Светодиоды')),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Здесь светодиод AIoT привязывается к состоянию: работе Hybrid Failover, процессу, доступности адреса или результату команды. Всё, что ядро умеет само, например трафик интерфейса, мигание или пульс, настраивается для любого светодиода на странице'),
				' ', E('a', { 'href': L.url('admin/system/leds') }, _('Индикаторы')), '.'
			])
		];

		if (st.error)
			return E([], head.concat([ E('p', {}, st.error) ]));

		return E([], head.concat([ E('div', { 'class': 'bl-cards' }, [ this.aiotCard(st) ]), this.about() ]));
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
				_('На плате есть белые и янтарные светодиоды. Яркость у них не регулируется, они либо горят, либо нет. Белый светодиод сети по умолчанию показывает трафик Wi-Fi 5 ГГц, белый системный горит, когда роутер загрузился. Янтарный системный показывает проблемы при загрузке. Светодиоды LAN и WAN у разъёмов показывают связь и трафик порта.')
			]),
			sec(_('Что настраивается на странице Индикаторы'), [
				_('Любому светодиоду там можно задать любой режим из тех, что умеет ядро: трафик или связь интерфейса, мигание с нужными интервалами, пульс, постоянное свечение и другие. По умолчанию янтарный светодиод сети уже стоит там как Wi-Fi 2.4GHz и мигает при трафике 2,4 ГГц, его можно изменить или удалить. В режиме MLO светодиод 5 ГГц сам переключается на общий интерфейс MLO.')
			]),
			sec(_('Светодиод AIoT'), [
				_('Белый светодиод AIoT свободен. Здесь он привязывается к тому, что ядро само отследить не может. Условия, которые можно выбрать'),
				[ _('Работа Hybrid Failover. Процесс запущен и таблица его правил в межсетевом экране на месте. Проверка каждые пять секунд.'),
				  _('Работа процесса. Горит, пока в системе есть процесс с таким именем.'),
				  _('Доступность интернета. Роутер раз в 15 секунд проверяет адрес командой ping.'),
				  _('Результат своей команды. Команда выполняется раз в пять секунд от имени root, светодиод показывает, завершилась ли она с кодом 0.') ],
				_('Выполненное условие можно показать горением или миганием, а логику перевернуть: тогда светодиод покажет, что условие не выполнено. Это удобно для сигнала о неполадке.')
			]),
			sec(_('Если светодиод уже настроен вами'), [
				_('Если вы сами назначили светодиод AIoT на странице Индикаторы, Beam WRT его не трогает, а здесь он помечен как занятый. Чтобы вернуть управление сюда, удалите свою настройку на той странице.')
			]),
			sec(_('Из консоли'), [
				E('pre', {}, '/usr/libexec/be7000-leds status\n/usr/libexec/be7000-leds aiot off\n/usr/libexec/be7000-leds aiot on')
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
