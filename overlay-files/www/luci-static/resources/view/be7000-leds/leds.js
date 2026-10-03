'use strict';
'require view';
'require rpc';
'require ui';

// System, LEDs: two indicator roles that the board can show but stock
// OpenWrt does not set up. The work is /usr/libexec/be7000-leds behind the
// rpcd object be7000-leds.

var callStatus = rpc.declare({ object: 'be7000-leds', method: 'status' });
var callSet = rpc.declare({ object: 'be7000-leds', method: 'set', params: [ 'what', 'on' ] });

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

		var ai = this.card(st.aiot, _('Hybrid Failover, белый AIoT'),
			st.aiot_on ? [ E('span', { 'class': 'bl-badge' }, _('горит')) ] : [],
			_('Светодиод AIoT горит, пока работает Hybrid Failover и его правила маршрутизации на месте. Если служба остановлена или упала, он гаснет.'),
			st.hf ? _('Применяется сразу.') : _('Hybrid Failover не установлен, светодиод не горит. Его можно поставить на странице Службы, Дополнения.'),
			'aiot', false);

		return E([], head.concat([ E('div', { 'class': 'bl-cards' }, [ w2, ai ]), this.about() ]));
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
			sec(_('Hybrid Failover'), [
				_('Белый светодиод AIoT проверяется каждые пять секунд. Он горит, если процесс Hybrid Failover работает и таблица его правил в межсетевом экране есть. Раньше узнать, что служба упала и трафик пошёл мимо неё, можно было только по странице службы.')
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
