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

    // interactivity
    var siteToggle = 1;
    document.querySelector('#showMain').addEventListener('click',function(e){
	var elements = document.querySelectorAll('.site');
	if(siteToggle == 1) { // hide site-elements
	    siteToggle = 0;
	    this.style.borderColor = '#333333';
	    this.style.background = 'repeating-linear-gradient(135deg, #000, #000 .4em, #333 .4em, #333 .8em)';
	    elements.map(function(l){this.style.display = 'none';});
	} else {                                  // show site-elements
	    siteToggle = 1;
	    this.style.borderColor = '#ffffff';
	    this.style.background = 'repeating-linear-gradient(135deg, #000, #000 .4em, #fff .4em, #fff .8em)';
	    elements.map(function(l){this.style.display = 'inline-block';});
	};
    });
    document.querySelectorAll('input').map(function(i){
	this.addEventListener("keydown",function(e){
	    e.stopPropagation();
	},false);
    });
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
	var selectNextNode = function(){
	    var cur = null;
	    if(window.location.hash)
		cur = document.querySelector(window.location.hash);
	    if(!cur)
		cur = last;
	    var start = cur;
	    do {
		cur = document.querySelector("[id='" + (cur.attr('next') || '') + "']");
	    } while ((cur != start) && (cur.attr('type') != 'node'));
	    window.location.hash = cur.attr('id');
	    e.preventDefault();
	};
	var selectPrevNode = function(){
	    var cur = null;
	    if(window.location.hash)
		cur = document.querySelector(window.location.hash);
	    if(!cur)
		cur = first;
	    var start = cur;
	    do {
		cur = document.querySelector("[id='" + (cur.attr('prev') || '') + "']");
	    } while ((cur != start) && (cur.attr('type') != 'node'));
	    window.location.hash = cur.attr('id');
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
	    if(key==37) // [shift-left] previous page
		gotoLink('prev');
	    if(key==39) // [shift-right] next page
		gotoLink('next');
	    if(key==38) // [shift-up] up to parent
		gotoLink('up');
	    if(key==40) // [shift-down] show children
		gotoLink('down');
	    if(key==80) // [shift-P] previous node
		selectPrevNode();
	    if(key==78) // [shift-N] next node
		selectNextNode();
	} else {
	    if(key==80) // [p]revious link
		selectPrevLink();
	    if(key==78) // [n]ext link
		selectNextLink();
	};
    },false);
}, false);
