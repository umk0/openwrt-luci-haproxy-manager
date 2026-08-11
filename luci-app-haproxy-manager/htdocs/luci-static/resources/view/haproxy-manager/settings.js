'use strict';
/* global hmUi */
'require view';
'require form';
'require fs';
'require ui';
'require haproxy-manager.ui as hmUi';

return view.extend({
	render: function() {
		var m, s, o;

		hmUi.ensureStyles();

		m = new form.Map('haproxy_manager', _('HAProxy Settings'),
			_('Configure shared Web entry ports, router access, and firewall automation.'));

		s = m.section(form.NamedSection, 'main', 'settings', _('HAProxy service'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable managed configuration'));
		o.default = '0';

		o = s.option(form.Value, 'wan_bind_ip', _('WAN bind address'));
		o.placeholder = _('Automatic');
		o.default = 'auto';
		o.rmempty = false;

		s = m.section(form.NamedSection, 'main', 'settings', _('Web entry ports'));
		s.anonymous = true;
		s.description = _('Every Web service shares these public ports. SSH, Remote Desktop, and Custom TCP services use the ports configured on each service.');

		o = s.option(form.Value, 'http_port', _('Public HTTP port'));
		o.datatype = 'port';
		o.default = '80';
		o.rmempty = false;

		o = s.option(form.Value, 'https_port', _('Public HTTPS port'));
		o.datatype = 'port';
		o.default = '443';
		o.rmempty = false;

		s = m.section(form.NamedSection, 'main', 'settings', _('Router access'));
		s.anonymous = true;

		o = s.option(form.Flag, 'manage_uhttpd_bind', _('Keep LuCI on the LAN address'));
		o.default = '0';
		o.description = _('Recommended when HAProxy uses public ports 80 or 443. LuCI remains available from the local network.');

		o = s.option(form.Value, 'lan_bind_ip', _('LuCI LAN address'));
		o.placeholder = _('Automatic');
		o.default = 'auto';
		o.depends('manage_uhttpd_bind', '1');

		s = m.section(form.NamedSection, 'main', 'settings', _('Firewall automation'));
		s.anonymous = true;

		o = s.option(form.Flag, 'manage_firewall', _('Open HAProxy ports on WAN automatically'));
		o.default = '0';
		o.description = _('Creates and updates only firewall rules owned by HAProxy Manager.');

		o = s.option(form.Value, 'firewall_zone', _('WAN firewall zone'));
		o.default = 'wan';
		o.rmempty = false;
		o.depends('manage_firewall', '1');

		o = s.option(form.ListValue, 'firewall_conflict_mode', _('Existing port-forward conflicts'));
		o.value('warn', _('Stop and show conflicts'));
		o.value('disable', _('Disable conflicting forwards during apply'));
		o.default = 'warn';
		o.rmempty = false;
		o.depends('manage_firewall', '1');

		s = m.section(form.NamedSection, 'main', 'settings', _('Recovery'));
		s.anonymous = true;
		s.description = _('A restorable snapshot is created before migration and every apply.');

		return m.render().then(function(node) {
			var recoverySection = node.querySelectorAll('.cbi-section');
			var lastSection = recoverySection.length ? recoverySection[recoverySection.length - 1] : null;

			if (lastSection) {
				lastSection.appendChild(E('p', [
					E('a', {
						'class': 'btn cbi-button',
						'href': L.url('admin/services/haproxy-manager/status') + '#recovery'
					}, _('Open recovery'))
				]));
			}

			node.appendChild(E('div', { 'class': 'cbi-page-actions hm-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-save',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() {
						return m.save().then(function() {
							hmUi.notify(_('Settings saved'), 'info');
						}).catch(function(err) {
							hmUi.notifyError(err);
						});
					})
				}, _('Save settings')),
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() {
						return m.save().then(function() {
							return fs.exec('/usr/libexec/haproxy-manager/apply', []);
						}).then(function(r) {
							hmUi.notify(r.stdout || _('Applied'), 'info');
						}).catch(function(err) {
							hmUi.notifyError(err);
						});
					})
				}, _('Save and apply'))
			]));

			return node;
		}.bind(this));
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
