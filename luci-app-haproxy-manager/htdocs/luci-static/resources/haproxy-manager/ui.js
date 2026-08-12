'use strict';
'require baseclass';
'require fs';
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
	},

	exec: function(path, args) {
		return fs.exec(path, args || []).then(function(result) {
			if (!result.code)
				return result;

			var message = String(result.stderr || result.stdout ||
				_('Command failed with code %d.').format(result.code)).trim();
			var error = new Error(message);
			error.code = result.code;
			error.stdout = result.stdout;
			error.stderr = result.stderr;
			throw error;
		});
	}
});
