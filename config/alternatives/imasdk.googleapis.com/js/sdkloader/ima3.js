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
		    getSettings() {
			return google.ima.ImaSdkSettings;
		    };
		},
		AdsManagerLoadedEventTypes: class {
		    ADS_MANAGER_LOADED: any;
		},
		AdsManagerLoadedEvent: class {
		    static Type: AdsManagerLoadedEventTypes;
		},
		version: 1
	       }};

