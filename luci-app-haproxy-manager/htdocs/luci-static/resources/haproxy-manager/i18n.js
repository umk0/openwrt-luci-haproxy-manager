'use strict';
'require baseclass';
'require request';

var catalog = null;
var loading = null;

function normalizeLang(lang) {
	lang = String(lang || '').toLowerCase().replace(/_/g, '-');

	if (lang == 'zh' || lang.indexOf('zh-') == 0)
		return 'zh-cn';

	if (lang.indexOf('-') > -1)
		lang = lang.split('-')[0];

	return lang;
}

function candidateLangs() {
	var seen = {};
	var langs = [];
	var raw = [
		L.env && (L.env.lang || L.env.language),
		document.documentElement && document.documentElement.getAttribute('lang'),
		navigator.language
	];

	for (var i = 0; i < raw.length; i++) {
		var lang = normalizeLang(raw[i]);

		if (!lang || lang == 'en' || seen[lang])
			continue;

		seen[lang] = true;
		langs.push(lang);
	}

	return langs;
}

function loadCandidate(langs, index) {
	if (index >= langs.length)
		return {};

	var lang = langs[index];
	var url = L.resource('i18n/haproxy-manager.%s.json'.format(lang));

	return request.get(url, { cache: true }).then(function(res) {
		if (!res.ok)
			return loadCandidate(langs, index + 1);

		return res.json();
	}).catch(function() {
		return loadCandidate(langs, index + 1);
	});
}

return baseclass.extend({
	load: function() {
		if (catalog != null)
			return Promise.resolve(catalog);

		if (loading != null)
			return loading;

		loading = loadCandidate(candidateLangs(), 0).then(function(data) {
			catalog = data || {};
			return catalog;
		});

		return loading;
	},

	t: function(message) {
		return (catalog && catalog[message]) || message;
	}
});
