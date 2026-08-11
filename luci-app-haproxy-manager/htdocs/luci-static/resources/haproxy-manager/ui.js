'use strict';
'require baseclass';
'require ui';

return baseclass.extend({
	ensureStyles: function() {
		if (document.querySelector('link[data-haproxy-manager-style]'))
			return;

		document.head.appendChild(E('link', {
			'rel': 'stylesheet',
			'href': L.resource('haproxy-manager/style.css'),
			'data-haproxy-manager-style': '1'
		}));
	},

	notify: function(message, level) {
		ui.addNotification(null, E('pre', { 'class': 'hm-notification' }, String(message || '').trim()), level || 'info');
	},

	notifyError: function(error) {
		this.notify(error && error.message ? error.message : String(error), 'danger');
	}
});
