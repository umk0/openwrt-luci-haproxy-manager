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
			t('Configure shared Web entry ports, router access, and firewall automation.'));

		s = m.section(form.NamedSection, 'main', 'settings', t('HAProxy service'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', t('Enable managed configuration'));
		o.default = '0';

		o = s.option(form.Value, 'wan_bind_ip', t('WAN bind address'));
		o.placeholder = t('Automatic');
		o.default = 'auto';
		o.rmempty = false;

		s = m.section(form.NamedSection, 'main', 'settings', t('Web entry ports'));
		s.anonymous = true;
		s.description = t('Every Web service shares these public ports. SSH, Remote Desktop, and Custom TCP services use the ports configured on each service.');

		o = s.option(form.Value, 'http_port', t('Public HTTP port'));
		o.datatype = 'port';
		o.default = '80';
		o.rmempty = false;

		o = s.option(form.Value, 'https_port', t('Public HTTPS port'));
		o.datatype = 'port';
		o.default = '443';
		o.rmempty = false;

		s = m.section(form.NamedSection, 'main', 'settings', t('Router access'));
		s.anonymous = true;

		o = s.option(form.Flag, 'manage_uhttpd_bind', t('Keep LuCI on the LAN address'));
		o.default = '0';
		o.description = t('Recommended when HAProxy uses public ports 80 or 443. LuCI remains available from the local network.');

		o = s.option(form.Value, 'lan_bind_ip', t('LuCI LAN address'));
		o.placeholder = t('Automatic');
		o.default = 'auto';
		o.depends('manage_uhttpd_bind', '1');

		s = m.section(form.NamedSection, 'main', 'settings', t('Firewall automation'));
		s.anonymous = true;

		o = s.option(form.Flag, 'manage_firewall', t('Open HAProxy ports on WAN automatically'));
		o.default = '0';
		o.description = t('Creates and updates only firewall rules owned by HAProxy Manager.');

		o = s.option(form.Value, 'firewall_zone', t('WAN firewall zone'));
		o.default = 'wan';
		o.rmempty = false;
		o.depends('manage_firewall', '1');

		o = s.option(form.ListValue, 'firewall_conflict_mode', t('Existing port-forward conflicts'));
		o.value('warn', t('Stop and show conflicts'));
		o.value('disable', t('Disable conflicting forwards during apply'));
		o.default = 'warn';
		o.rmempty = false;
		o.depends('manage_firewall', '1');

		s = m.section(form.NamedSection, 'main', 'settings', t('Recovery'));
		s.anonymous = true;
		s.description = t('A restorable snapshot is created before migration and every apply.');

		return m.render().then(function(node) {
			var recoverySection = node.querySelectorAll('.cbi-section');
			var lastSection = recoverySection.length ? recoverySection[recoverySection.length - 1] : null;

			if (lastSection) {
				lastSection.appendChild(E('p', [
					E('a', {
						'class': 'btn cbi-button',
						'href': L.url('admin/services/haproxy-manager/status') + '#recovery'
					}, t('Open recovery'))
				]));
			}

			node.appendChild(E('div', { 'class': 'cbi-page-actions hm-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-save',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() {
						return m.save().then(function() {
							hmUi.notify(t('Settings saved'), 'info');
						}).catch(function(err) {
							hmUi.notifyError(err);
						});
					})
				}, t('Save settings')),
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
				}, t('Save and apply'))
			]));

			return node;
		}.bind(this));
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
