google = {ima: {ImaSdkSettings: {VpaidMode: {ENABLED: 1},
				 setPlayerVersion: function(v){},
				 setPlayerType: function(t){},
				},
		settings: {setVpaidMode: function(bool){
		    console.log('Welcome to IMA');
		}},
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
		version: 1
	       }};

