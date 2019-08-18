google = {ima: {ImaSdkSettings: {VpaidMode: {ENABLED: 1},
				 setAutoPlayAdBreaks: function(a){},
				 setPlayerVersion: function(v){},
				 setPlayerType: function(t){},
				 setVpaidMode: function(b){}
				},
	       	AdDisplayContainer: class {
		    constructor(a,b,c,d) {
			console.log('..new display container');
		    };
		},
		AdsLoader: class {
		    constructor(a) {
			console.log('..new ad loader');
		    };
		    addEventListener(a,b,c) {};
		    getSettings() {
			return google.ima.ImaSdkSettings;
		    };
		},
		AdErrorEvent: {Type: {AD_ERROR: 1}},
		AdsManagerLoadedEvent: {Type: {ADS_MANAGER_LOADED: 1}},
		version: 1
	       }};

