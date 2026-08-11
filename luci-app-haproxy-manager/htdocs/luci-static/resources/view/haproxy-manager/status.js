'use strict';
'require view';
'require fs';
'require ui';
'require haproxy-manager.i18n as hmI18n';
'require haproxy-manager.ui as hmUi';

function parseStatus(output) {
	var status = { listeners: [] };
	var lines = String(output || '').split(/\r?\n/);

	for (var i = 0; i < lines.length; i++) {
		var fields = lines[i].split('\t');

		if (fields[0] == 'listener') {
			status.listeners.push({
				protocol: fields[1] || '',
				address: fields[2] || '',
				process: fields.slice(3).join('\t') || ''
			});
		}
		else if (fields[0]) {
			status[fields[0]] = fields.slice(1).join('\t');
		}
	}

	return status;
}

function statusItem(label, value) {
	return E('div', { 'class': 'hm-status-item' }, [
		E('span', { 'class': 'hm-status-label' }, label),
		E('span', { 'class': 'hm-status-value' }, value)
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			hmI18n.load(),
			fs.exec('/usr/libexec/haproxy-manager/status', []).catch(function(err) {
				return { stdout: '', stderr: err.message || String(err), code: 1 };
			})
		]);
	},

	showRollback: function(t) {
		ui.showModal(t('Rollback last configuration?'), [
			E('p', t('This restores the last HAProxy, firewall, and LuCI backup, then restarts the services.')),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn cbi-button',
					'type': 'button',
					'click': ui.hideModal
				}, t('Cancel')),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-negative important',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() {
						return fs.exec('/usr/libexec/haproxy-manager/rollback', [ 'last' ]).then(function(r) {
							ui.hideModal();
							hmUi.notify(r.stdout || t('Rolled back'), 'info');
							window.setTimeout(function() { window.location.reload(); }, 800);
						}).catch(function(err) {
							ui.hideModal();
							hmUi.notifyError(err);
						});
					})
				}, t('Confirm rollback'))
			])
		]);
	},

	render: function(data) {
		var res = data[1];
		var status = parseStatus(res.stdout);
		var t = function(message) { return hmI18n.t(message); };
		var running = status.service == 'running';
		var listeners = status.listeners.map(function(listener) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'data-title': t('Protocol') }, listener.protocol),
				E('td', { 'class': 'td', 'data-title': t('Address') }, E('code', listener.address)),
				E('td', { 'class': 'td', 'data-title': t('Process') }, listener.process)
			]);
		});

		hmUi.ensureStyles();

		if (!listeners.length) {
			listeners.push(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td', 'colspan': '3' }, t('No HAProxy or LuCI listeners detected.'))
			]));
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', t('HAProxy Status')),
			E('div', { 'class': 'cbi-map-descr' }, t('Service health and active listeners.')),
			res.code && res.stderr ? E('div', { 'class': 'alert-message error' }, res.stderr) : '',
			E('div', { 'class': 'hm-status-grid' }, [
				statusItem(t('Service'), E('span', {
					'class': 'hm-state %s'.format(running ? 'hm-state-on' : 'hm-state-off')
				}, t(running ? 'Running' : 'Stopped'))),
				statusItem(t('WAN address'), status.wan_ip || t('Not set')),
				statusItem(t('HAProxy version'), status.version || t('Not available')),
				statusItem(t('Last backup'), status.last_backup == 'none' ? t('None') : (status.last_backup || t('None')))
			]),
			E('h3', t('Active listeners')),
			E('table', { 'class': 'table hm-listener-table' }, [
				E('thead', E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, t('Protocol')),
					E('th', { 'class': 'th' }, t('Address')),
					E('th', { 'class': 'th' }, t('Process'))
				])),
				E('tbody', listeners)
			]),
			E('div', { 'class': 'cbi-page-actions hm-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'type': 'button',
					'click': function() { window.location.reload(); }
				}, t('Refresh')),
				E('button', {
					'class': 'btn cbi-button cbi-button-reset',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() { this.showRollback(t); })
				}, t('Rollback'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
