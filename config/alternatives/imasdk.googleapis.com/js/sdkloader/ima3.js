google = {ima: {ImaSdkSettings: {VpaidMode: {ENABLED: 1}},
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
		}
	       }};

