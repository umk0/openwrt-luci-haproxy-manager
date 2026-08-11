'use strict';
'require view';
'require fs';
'require ui';
'require haproxy-manager.i18n as hmI18n';
'require haproxy-manager.ui as hmUi';

function parseStatus(output) {
	var status = { listeners: [] };

	String(output || '').split(/\r?\n/).forEach(function(line) {
		var fields = line.split('\t');
		if (fields[0] == 'listener') {
			status.listeners.push({
				protocol: fields[1] || '',
				address: fields[2] || '',
				process: fields.slice(3).join('\t') || ''
			});
		}
		else if (fields[0])
			status[fields[0]] = fields.slice(1).join('\t');
	});

	return status;
}

function parseBackups(output) {
	return String(output || '').split(/\r?\n/).map(function(line) {
		var fields = line.split('\t');
		return fields[0] == 'backup' ? { id: fields[1], latest: fields[2] == '1', files: fields[3] } : null;
	}).filter(Boolean);
}

function parseFirewall(output) {
	var result = { conflicts: '0', enabled: '0', policy: '' };
	String(output || '').split(/\r?\n/).forEach(function(line) {
		var fields = line.split('\t');
		if (fields[0] && fields[0] != 'conflict' && fields[0] != 'port')
			result[fields[0]] = fields.slice(1).join('\t');
	});
	return result;
}

function backupDate(id) {
	var match = String(id || '').match(/^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})$/);
	return match ? '%s-%s-%s %s:%s:%s'.format(match[1], match[2], match[3], match[4], match[5], match[6]) : id;
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
			}),
			fs.exec('/usr/libexec/haproxy-manager/backups', []).catch(function() { return { stdout: '' }; }),
			fs.exec('/usr/libexec/haproxy-manager/firewall-plan', []).catch(function() { return { stdout: '' }; })
		]);
	},

	showRestore: function(t, backupId) {
		ui.showModal(t('Restore configuration?'), [
			E('p', t('HAProxy, firewall, and LuCI settings will be restored from %s.').format(backupDate(backupId))),
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
						return fs.exec('/usr/libexec/haproxy-manager/rollback', [ backupId ]).then(function(r) {
							ui.hideModal();
							hmUi.notify(r.stdout || t('Restored'), 'info');
							window.setTimeout(function() { window.location.reload(); }, 900);
						}).catch(function(err) {
							ui.hideModal();
							hmUi.notifyError(err);
						});
					})
				}, t('Restore'))
			])
		]);
	},

	render: function(data) {
		var res = data[1];
		var status = parseStatus(res.stdout);
		var backups = parseBackups(data[2].stdout);
		var firewall = parseFirewall(data[3].stdout);
		var t = function(message) { return hmI18n.t(message); };
		var running = status.service == 'running';
		var firewallText = firewall.enabled != '1' ? t('Manual') : +firewall.conflicts > 0 ?
			t('%d conflicts').format(+firewall.conflicts) : t('Managed');
		var listeners = status.listeners.map(function(listener) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'data-title': t('Protocol') }, listener.protocol),
				E('td', { 'class': 'td', 'data-title': t('Address') }, E('code', listener.address)),
				E('td', { 'class': 'td', 'data-title': t('Process') }, listener.process)
			]);
		});
		var backupRows = backups.map(function(backup) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'data-title': t('Created') }, [
					E('span', backupDate(backup.id)),
					backup.latest ? E('span', { 'class': 'hm-badge hm-backup-latest' }, t('Latest')) : ''
				]),
				E('td', { 'class': 'td', 'data-title': t('Contents') }, t('%d configuration files').format(+backup.files || 0)),
				E('td', { 'class': 'td cbi-section-actions' }, E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() { this.showRestore(t, backup.id); })
				}, t('Restore')))
			]);
		}.bind(this));

		hmUi.ensureStyles();

		if (!listeners.length) {
			listeners.push(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td', 'colspan': '3' }, t('No HAProxy or LuCI listeners detected.'))
			]));
		}

		if (!backupRows.length) {
			backupRows.push(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td', 'colspan': '3' }, t('No recovery points yet.'))
			]));
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', t('HAProxy Status')),
			E('div', { 'class': 'cbi-map-descr' }, t('Service health, active listeners, and recovery points.')),
			res.code && res.stderr ? E('div', { 'class': 'alert-message error' }, res.stderr) : '',
			E('div', { 'class': 'hm-status-grid' }, [
				statusItem(t('Service'), E('span', {
					'class': 'hm-state %s'.format(running ? 'hm-state-on' : 'hm-state-off')
				}, t(running ? 'Running' : 'Stopped'))),
				statusItem(t('WAN address'), status.wan_ip || t('Not set')),
				statusItem(t('HAProxy version'), status.version || t('Not available')),
				statusItem(t('Firewall'), E('span', {
					'class': 'hm-state %s'.format(+firewall.conflicts > 0 ? 'hm-state-danger' : firewall.enabled == '1' ? 'hm-state-on' : 'hm-state-off')
				}, firewallText))
			]),
			E('h3', t('Active listeners')),
			E('table', { 'class': 'table hm-listener-table' }, [
				E('thead', {}, [ E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, t('Protocol')),
					E('th', { 'class': 'th' }, t('Address')),
					E('th', { 'class': 'th' }, t('Process'))
				]) ]),
				E('tbody', {}, listeners)
			]),
			E('div', { 'id': 'recovery', 'class': 'hm-section-heading' }, [
				E('div', { 'class': 'hm-section-title-row' }, [
					E('h3', t('Recovery points')),
					E('button', {
						'class': 'btn cbi-button cbi-button-add',
						'type': 'button',
						'click': ui.createHandlerFn(this, function() {
							return fs.exec('/usr/libexec/haproxy-manager/backup', []).then(function() {
								window.location.reload();
							}).catch(function(err) { hmUi.notifyError(err); });
						})
					}, t('Create recovery point'))
				]),
				E('p', { 'class': 'cbi-section-descr' }, t('Restore HAProxy, firewall, and LuCI settings from a previous snapshot.'))
			]),
			E('table', { 'class': 'table hm-backup-table' }, [
				E('thead', {}, [ E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, t('Created')),
					E('th', { 'class': 'th' }, t('Contents')),
					E('th', { 'class': 'th' })
				]) ]),
				E('tbody', {}, backupRows)
			]),
			E('div', { 'class': 'cbi-page-actions hm-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'type': 'button',
					'click': function() { window.location.reload(); }
				}, t('Refresh'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
