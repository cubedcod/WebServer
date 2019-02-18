NodeList.prototype.map = function(f,a){
    for(var i=0, l=this.length; i<l; i++)
	f.apply(this[i],a);
    return this;
};
Element.prototype.attr = function(a,v){
    if(v){
	this.setAttribute(a,String(v));
	return this;
    } else {
	return this.getAttribute(a);
    };
};
document.addEventListener("DOMContentLoaded", function(){

    var first = null;
    var last = null;

    // construct selection-ring
    document.querySelectorAll('[id]').map(function(e){
	if(!first)
	    first = this;	
	if(last){ // link to prior
	    this.attr('prev',last.attr('id'));
	    last.attr('next',this.attr('id'));
	};
	last = this;
    });
    if(first && last){ // close ring
	last.attr('next',first.attr('id'));
	first.attr('prev',last.attr('id'));
    };

    // keyboard control
    document.addEventListener("keydown",function(e){
	var key = e.keyCode;
	var selectNextLink = function(){
	    var cur = null;
	    if(window.location.hash)
		cur = document.querySelector(window.location.hash);
	    if(!cur)
		cur = last;
	    window.location.hash = cur.attr('next');
	    e.preventDefault();
	};
	var selectPrevLink = function(){
	    var cur = null;
	    if(window.location.hash)
		cur = document.querySelector(window.location.hash);
	    if(!cur)
		cur = first;
	    window.location.hash = cur.attr('prev');;
	    e.preventDefault();
	};
	var gotoLink = function(arc) {
	    var doc = document.querySelector("link[rel='" + arc + "']");
	    if(doc)
		window.location = doc.getAttribute('href');
	};
	var gotoHref = function(){
	    if(window.location.hash){
		cur = document.querySelector(window.location.hash);
		if(cur){
		    href = cur.attr('href');
		    if(href)
			window.location = href;
		};
	    };
	};
	if(e.getModifierState("Shift")) {
	    if(key==37||key==80) // [shift-left] previous page
		gotoLink('prev');
	    if(key==39||key==78) // [shift-right] next page
		gotoLink('next');
	    if(key==38) // [shift-up] up to parent
		gotoLink('up');
	    if(key==40) // [shift-down] show children
		gotoLink('down');
	} else {
	    if(key==80) // [p]revious link
		selectPrevLink();
	    if(key==78) // [n]ext link
		selectNextLink();
	    if(key==83) // [s]ort items
		gotoLink('sort');
	};
    },false);
}, false);
