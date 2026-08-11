'use strict';
'require view';
'require fs';
'require ui';
'require haproxy-manager.i18n as hmI18n';
'require haproxy-manager.ui as hmUi';

return view.extend({
	load: function() {
		return Promise.all([
			hmI18n.load(),
			fs.read('/etc/haproxy.cfg').catch(function() {
				return '';
			})
		]);
	},

	applyRaw: function(t, textarea) {
		ui.showModal(t('Apply raw configuration?'), [
			E('p', t('The file will be validated and backed up before HAProxy restarts.')),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn cbi-button',
					'type': 'button',
					'click': ui.hideModal
				}, t('Cancel')),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() {
						return fs.write('/tmp/haproxy-manager-raw.cfg', textarea.value).then(function() {
							return fs.exec('/usr/libexec/haproxy-manager/apply-raw-file', [ '/tmp/haproxy-manager-raw.cfg' ]);
						}).then(function(r) {
							ui.hideModal();
							hmUi.notify(r.stdout || t('Applied'), 'info');
						}).catch(function(err) {
							ui.hideModal();
							hmUi.notifyError(err);
						});
					})
				}, t('Apply'))
			])
		]);
	},

	render: function(data) {
		var cfg = data[1];
		var t = function(message) { return hmI18n.t(message); };
		var textarea = E('textarea', {
			'id': 'haproxy-raw-config',
			'class': 'cbi-input-textarea hm-raw-editor',
			'spellcheck': 'false',
			'aria-label': t('Raw HAProxy configuration')
		}, cfg || '');

		hmUi.ensureStyles();

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', t('Raw HAProxy Config')),
			E('div', { 'class': 'cbi-map-descr' }, t('Expert editor for /etc/haproxy.cfg.')),
			E('div', { 'class': 'alert-message warning' }, t('Generated routes can overwrite manual changes to this file.')),
			textarea,
			E('div', { 'class': 'cbi-page-actions hm-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() {
						return fs.write('/tmp/haproxy-manager-raw.cfg', textarea.value).then(function() {
							return fs.exec('/usr/libexec/haproxy-manager/validate', [ '/tmp/haproxy-manager-raw.cfg' ]);
						}).then(function(r) {
							hmUi.notify(r.stdout || t('Config is valid'), 'info');
						}).catch(function(err) {
							hmUi.notifyError(err);
						});
					})
				}, t('Validate')),
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() { this.applyRaw(t, textarea); })
				}, t('Apply raw config'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
