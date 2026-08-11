'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require haproxy-manager.i18n as hmI18n';
'require haproxy-manager.ui as hmUi';

return view.extend({
	load: function() {
		return hmI18n.load();
	},

	render: function() {
		var m, s, o;
		var t = function(message) { return hmI18n.t(message); };

		hmUi.ensureStyles();

		m = new form.Map('haproxy_manager', t('HAProxy Settings'),
			t('Configure listeners, LuCI binding, and backups.'));

		s = m.section(form.NamedSection, 'main', 'settings', t('Service'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', t('Enable managed configuration'));
		o.default = '0';

		o = s.option(form.Value, 'wan_bind_ip', t('WAN bind address'));
		o.placeholder = t('Automatic');
		o.default = 'auto';
		o.rmempty = false;

		s = m.section(form.NamedSection, 'main', 'settings', t('Listeners'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enable_http', t('HTTP listener'));
		o.default = '1';

		o = s.option(form.Value, 'http_port', t('HTTP port'));
		o.datatype = 'port';
		o.default = '80';
		o.depends('enable_http', '1');

		o = s.option(form.Flag, 'enable_https_passthrough', t('HTTPS SNI passthrough'));
		o.default = '0';

		o = s.option(form.Value, 'https_port', t('HTTPS port'));
		o.datatype = 'port';
		o.default = '443';
		o.depends('enable_https_passthrough', '1');

		s = m.section(form.NamedSection, 'main', 'settings', t('LuCI access'));
		s.anonymous = true;

		o = s.option(form.Flag, 'manage_uhttpd_bind', t('Bind LuCI to LAN only'));
		o.default = '0';
		o.description = t('Allows HAProxy to use the WAN address on HTTP and HTTPS ports.');

		o = s.option(form.Value, 'lan_bind_ip', t('LuCI LAN address'));
		o.placeholder = t('Automatic');
		o.default = 'auto';
		o.depends('manage_uhttpd_bind', '1');

		s = m.section(form.NamedSection, 'main', 'settings', t('Backups'));
		s.anonymous = true;

		o = s.option(form.Value, 'backup_dir', t('Backup directory'));
		o.default = '/root/haproxy-manager-backups';
		o.rmempty = false;

		return m.render().then(function(node) {
			node.appendChild(E('div', { 'class': 'cbi-page-actions hm-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-save',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() {
						return m.save().then(function() {
							hmUi.notify(t('Saved'), 'info');
						}).catch(function(err) {
							hmUi.notifyError(err);
						});
					})
				}, t('Save only')),
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() {
						return m.save().then(function() {
							return fs.exec('/usr/libexec/haproxy-manager/apply', []);
						}).then(function(r) {
							hmUi.notify(r.stdout || t('Applied'), 'info');
						}).catch(function(err) {
							hmUi.notifyError(err);
						});
					})
				}, t('Save & apply'))
			]));

			return node;
		}.bind(this));
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
