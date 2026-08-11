'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require haproxy-manager.i18n as hmI18n';
'require haproxy-manager.ui as hmUi';

function protocolLabel(t, protocol) {
	switch (protocol) {
	case 'https':
		return t('HTTPS SNI');
	case 'both':
		return t('HTTP + HTTPS');
	case 'tcp':
		return t('TCP');
	default:
		return t('HTTP Host');
	}
}

return view.extend({
	load: function() {
		return hmI18n.load();
	},

	render: function() {
		var m, s, o;
		var t = function(message) { return hmI18n.t(message); };

		hmUi.ensureStyles();

		m = new form.Map('haproxy_manager', t('HAProxy Routes'),
			t('Route HTTP, HTTPS SNI, and TCP traffic to services on your network.'));

		s = m.section(form.GridSection, 'route', t('Routes'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.addbtntitle = t('Add route');

		o = s.option(form.Flag, 'enabled', t('Enabled'));
		o.default = '1';
		o.modalonly = true;

		o = s.option(form.Value, 'name', t('Name'));
		o.placeholder = t('My service');
		o.rmempty = true;
		o.modalonly = true;

		o = s.option(form.ListValue, 'protocol', t('Protocol'));
		o.value('http', t('HTTP Host'));
		o.value('https', t('HTTPS SNI passthrough'));
		o.value('both', t('HTTP + HTTPS'));
		o.value('tcp', t('TCP port forward'));
		o.default = 'http';
		o.modalonly = true;

		o = s.option(form.Value, 'host', t('Domain'));
		o.placeholder = 'example.org';
		o.description = t('Domain matched from the HTTP Host header or TLS SNI.');
		o.rmempty = false;
		o.modalonly = true;
		o.depends('protocol', 'http');
		o.depends('protocol', 'https');
		o.depends('protocol', 'both');

		o = s.option(form.Value, 'listen_port', t('WAN listen port'));
		o.datatype = 'port';
		o.placeholder = '8443';
		o.description = t('For TCP routes only. Leave empty to use the backend port.');
		o.rmempty = true;
		o.modalonly = true;
		o.depends('protocol', 'tcp');

		o = s.option(form.Value, 'backend_host', t('Backend host'));
		o.placeholder = '192.0.2.10';
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'backend_port', t('Backend port'));
		o.datatype = 'port';
		o.placeholder = '80';
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.DummyValue, '_status', t('Status'));
		o.modalonly = false;
		o.textvalue = function(sectionId) {
			var enabled = m.data.get('haproxy_manager', sectionId, 'enabled') != '0';

			return E('span', {
				'class': 'hm-state %s'.format(enabled ? 'hm-state-on' : 'hm-state-off')
			}, t(enabled ? 'On' : 'Off'));
		};

		o = s.option(form.DummyValue, '_name', t('Name'));
		o.modalonly = false;
		o.textvalue = function(sectionId) {
			var name = m.data.get('haproxy_manager', sectionId, 'name');
			var enabled = m.data.get('haproxy_manager', sectionId, 'enabled') != '0';
			var protocol = m.data.get('haproxy_manager', sectionId, 'protocol') || 'http';
			var host = m.data.get('haproxy_manager', sectionId, 'host');
			var port = m.data.get('haproxy_manager', sectionId, 'listen_port') ||
				m.data.get('haproxy_manager', sectionId, 'backend_port');
			var displayName = name || host || '%s %s'.format(protocolLabel(t, protocol), port || '');

			return E('div', { 'class': 'hm-route-name' }, [
				E('span', displayName),
				E('span', {
					'class': 'hm-state hm-mobile-only %s'.format(enabled ? 'hm-state-on' : 'hm-state-off')
				}, t(enabled ? 'On' : 'Off'))
			]);
		};

		o = s.option(form.DummyValue, '_endpoint', t('Public endpoint'));
		o.modalonly = false;
		o.textvalue = function(sectionId) {
			var protocol = m.data.get('haproxy_manager', sectionId, 'protocol') || 'http';
			var host = m.data.get('haproxy_manager', sectionId, 'host');
			var listenPort = m.data.get('haproxy_manager', sectionId, 'listen_port') ||
				m.data.get('haproxy_manager', sectionId, 'backend_port');
			var endpoint = protocol == 'tcp' ? ':%s'.format(listenPort || '') : (host || t('Not set'));

			return E('div', { 'class': 'hm-endpoint' }, [
				E('span', { 'class': 'hm-badge' }, protocolLabel(t, protocol)),
				E('span', { 'class': 'hm-endpoint-value' }, endpoint)
			]);
		};

		o = s.option(form.DummyValue, '_destination', t('Destination'));
		o.modalonly = false;
		o.textvalue = function(sectionId) {
			var host = m.data.get('haproxy_manager', sectionId, 'backend_host') || t('Not set');
			var port = m.data.get('haproxy_manager', sectionId, 'backend_port') || '';

			return E('code', { 'class': 'hm-destination' }, '%s%s'.format(host, port ? ':' + port : ''));
		};

		return m.render().then(function(node) {
			var rows;
			var filterInput = E('input', {
				'id': 'haproxy-route-filter',
				'class': 'cbi-input-text hm-filter',
				'type': 'search',
				'placeholder': t('Filter routes'),
				'aria-label': t('Filter routes')
			});
			var countNode = E('span', { 'class': 'hm-route-count' });
			var emptyNode = E('p', {
				'class': 'alert-message notice hm-filter-empty',
				'hidden': ''
			}, t('No matching routes'));
			var toolbar = E('div', { 'class': 'hm-toolbar' }, [ filterInput, countNode ]);
			var section = node.querySelector('.cbi-section');

			function updateFilter() {
				var query = filterInput.value.trim().toLowerCase();
				var visible = 0;

				rows = node.querySelectorAll('.cbi-section-table-row[data-sid]');
				for (var i = 0; i < rows.length; i++) {
					var match = !query || rows[i].textContent.toLowerCase().indexOf(query) > -1;
					rows[i].hidden = !match;
					visible += match ? 1 : 0;
				}

				countNode.textContent = t('Shown: %d').format(visible);
				emptyNode.hidden = visible > 0 || !query;
			}

			filterInput.addEventListener('input', updateFilter);

			if (section) {
				var table = section.querySelector('.table');
				if (table)
					table.classList.add('hm-route-table');
				section.insertBefore(toolbar, table || section.firstChild);
				section.appendChild(emptyNode);
			}

			if (m.data.get('haproxy_manager', 'main', 'enabled') != '1') {
				node.insertBefore(E('div', { 'class': 'alert-message warning' }, [
					E('span', t('HAProxy configuration is disabled.')),
					' ',
					E('a', { 'href': L.url('admin/services/haproxy-manager/settings') }, t('Open settings'))
				]), node.firstChild.nextSibling);
			}

			node.appendChild(E('div', { 'class': 'cbi-page-actions hm-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'type': 'button',
					'click': ui.createHandlerFn(this, function() {
						return m.save().then(function() {
							return fs.exec('/usr/libexec/haproxy-manager/generate', [ '/tmp/haproxy-manager-preview.cfg' ]);
						}).then(function() {
							return fs.exec('/usr/libexec/haproxy-manager/validate', [ '/tmp/haproxy-manager-preview.cfg' ]);
						}).then(function(r) {
							hmUi.notify(r.stdout || t('Generated config is valid'), 'info');
						}).catch(function(err) {
							hmUi.notifyError(err);
						});
					})
				}, t('Validate changes')),
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

			updateFilter();
			return node;
		}.bind(this));
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
