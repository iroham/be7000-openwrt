'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({ object: 'be7000-wifi5g', method: 'status' });
var callSet = rpc.declare({ object: 'be7000-wifi5g', method: 'set', params: ['split'] });

var T = {
	ru: {
		title: '5 ГГц: одно или два радио',
		intro: 'Радиомодуль 5 ГГц (QCN9274) умеет работать как одно радио на весь диапазон или как два независимых, как 5G-1 и 5G-2 в стоке: нижнее на каналах 36–64 и верхнее на 149–165. Во втором случае у каждой половины свой канал и свои клиенты.',
		now: 'Сейчас',
		single: 'одно радио на весь диапазон 5 ГГц',
		split: 'два радио: 36–64 и 149–165',
		on: 'Разделить на два радио',
		off: 'Вернуть одно радио',
		busy: 'Переключаю, это занимает до минуты. Wi-Fi 5 ГГц на это время пропадёт.',
		note: 'При разделении у нижнего радио появляется копия сетей 5 ГГц с теми же именами и паролями. Каналы: 36 внизу и 149 вверху, их можно поменять на странице Беспроводная сеть. Выбор сохраняется и переживает перезагрузку и обновление.',
		na: 'Недоступно: в этой сборке нет драйвера с поддержкой разделения.'
	},
	en: {
		title: '5 GHz: one radio or two',
		intro: 'The 5 GHz module (QCN9274) can run as one radio for the whole band or as two independent ones, like 5G-1 and 5G-2 on stock: the lower on channels 36-64 and the upper on 149-165. Then each half has its own channel and its own clients.',
		now: 'Now',
		single: 'one radio for the whole 5 GHz band',
		split: 'two radios: 36-64 and 149-165',
		on: 'Split into two radios',
		off: 'Back to one radio',
		busy: 'Switching, this takes up to a minute. 5 GHz Wi-Fi is down meanwhile.',
		note: 'On split the lower radio gets copies of the 5 GHz networks with the same names and passwords. Channels start at 36 below and 149 above, you can change them on the Wireless page. The choice is kept across reboots and updates.',
		na: 'Not available: this build has no driver support for the split.'
	}
};

return view.extend({
	load: function() {
		return callStatus();
	},

	render: function(st) {
		var tx = T[/^en/i.test(document.documentElement.lang || '') ? 'en' : 'ru'];
		var mode = E('strong', {});
		var busy = E('p', { 'class': 'alert-message notice', 'style': 'display:none' }, tx.busy);
		var btn = E('button', { 'class': 'cbi-button cbi-button-action' });

		function update(s) {
			mode.textContent = s.split ? tx.split : tx.single;
			btn.textContent = s.split ? tx.off : tx.on;
			btn.disabled = !s.available || s.running;
			busy.style.display = s.running ? '' : 'none';
			btn.dataset.split = s.split ? '1' : '0';
		}

		btn.addEventListener('click', function() {
			var want = btn.dataset.split != '1';
			btn.disabled = true;
			busy.style.display = '';
			callSet(want).then(function() {
				window.setTimeout(function() { callStatus().then(update); }, 3000);
			});
		});

		update(st);
		poll.add(function() { return callStatus().then(update); }, 5);

		return E('div', {}, [
			E('h2', {}, tx.title),
			E('p', {}, tx.intro),
			st.available ? '' : E('p', { 'class': 'alert-message warning' }, tx.na),
			E('p', {}, [ tx.now + ': ', mode ]),
			busy,
			E('div', { 'class': 'cbi-page-actions', 'style': 'text-align:left' }, [ btn ]),
			E('p', { 'style': 'color:#888' }, tx.note)
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
