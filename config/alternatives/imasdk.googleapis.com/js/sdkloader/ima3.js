google = {ima: {ImaSdkSettings: {VpaidMode: {ENABLED: 1},
				 setAutoPlayAdBreaks: function(a){},
				 setPlayerVersion: function(v){},
				 setPlayerType: function(t){},
				 setVpaidMode: function(b){}
				},
	       	AdDisplayContainer: class {
		    constructor(a,b,c,d) {};
		    initialize() {};
		},
		AdsLoader: class {
		    constructor(a) {};
		    addEventListener(a,b,c) {};
		    contentComplete() {};
		    getSettings() {
			return google.ima.ImaSdkSettings;
		    };
		    requestAds(a,b) {};
		},
		AdsRequest: class {
		    constructor(a) {};
		    setAdWillAutoPlay(a) {};
		    setAdWillPlayMuted(a) {};
		},
		AdErrorEvent: {Type: {AD_ERROR: 1}},
		AdsManagerLoadedEvent: {Type: {ADS_MANAGER_LOADED: 1}},
		settings: {setDisableCustomPlaybackForIOS10Plus: function(a){},
			   setLocale: function(a){}},
		version: 1
	       }};

