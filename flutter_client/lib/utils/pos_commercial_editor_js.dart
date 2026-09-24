/// Lệnh soạn trong trang A4 (web iframe và WebView điện thoại dùng chung).
const posCommercialEditorScript = r'''
function sboxBlock(){
  var sel = window.getSelection();
  var n = sel && sel.anchorNode;
  if(!n) return null;
  if(n.nodeType===3) n = n.parentElement;
  while(n && n!==document.body){
    var t = n.tagName;
    if(t==='P'||t==='DIV'||t==='H1'||t==='H2'||t==='H3'||t==='LI'||t==='TD'||t==='TH') return n;
    n = n.parentElement;
  }
  return document.body;
}
function sboxStyle(prop, val){
  var el = sboxBlock();
  if(!el || el===document.body){
    try{ document.execCommand('formatBlock', false, 'p'); }catch(e){}
    el = sboxBlock();
  }
  if(!el) return;
  el.style[prop] = val;
  if(window._sboxFlush) _sboxFlush();
}
function sboxFontPt(pt){
  var sel = window.getSelection();
  if(sel && !sel.isCollapsed){
    var span = document.createElement('span');
    span.style.fontSize = pt+'pt';
    try{
      var range = sel.getRangeAt(0);
      span.appendChild(range.extractContents());
      range.insertNode(span);
    }catch(e){ sboxStyle('fontSize', pt+'pt'); }
  }else{
    sboxStyle('fontSize', pt+'pt');
  }
  if(window._sboxFlush) _sboxFlush();
}
function sboxImg(){
  var sel = window.getSelection();
  var n = sel && sel.anchorNode;
  if(n && n.nodeType===3) n = n.parentElement;
  var img = n && n.closest ? n.closest('img') : null;
  if(!img && n){
    var box = n.closest ? n.closest('.sbox-img') : null;
    if(box) img = box.querySelector('img');
  }
  if(!img) img = document.querySelector('img.sbox-last');
  return img;
}
function sboxInsertImage(src){
  document.querySelectorAll('img.sbox-last').forEach(function(im){ im.classList.remove('sbox-last'); });
  var html = '<p style="text-align:center;margin:8px 0"><span class="sbox-img" contenteditable="false" style="display:inline-block;max-width:100%"><img class="sbox-last" src="'+src.replace(/"/g,'&quot;')+'" style="width:160px;max-width:100%;height:auto" /></span></p>';
  document.execCommand('insertHTML', false, html);
  if(window._sboxFlush) _sboxFlush();
}
function sboxImageWidth(delta){
  var img = sboxImg();
  if(!img) return;
  var w = parseFloat(img.style.width) || img.getBoundingClientRect().width || 160;
  img.style.width = Math.max(48, Math.min(w+delta, 680))+'px';
  img.style.height = 'auto';
  if(window._sboxFlush) _sboxFlush();
}
function sboxImageAlign(align){
  var img = sboxImg();
  if(!img) return;
  var p = img.closest ? img.closest('p,div') : null;
  if(p) p.style.textAlign = align;
  if(window._sboxFlush) _sboxFlush();
}
function sboxCell(){
  var el = sboxBlock();
  if(!el) return null;
  return el.closest ? el.closest('td,th') : (el.tagName==='TD'||el.tagName==='TH'?el:null);
}
function sboxTableRow(add){
  var td = sboxCell();
  if(!td) return;
  var tr = td.parentElement;
  var table = tr.closest('table');
  if(add){
    var clone = tr.cloneNode(true);
    clone.querySelectorAll('td,th').forEach(function(c){ c.innerHTML='&nbsp;'; c.removeAttribute('colspan'); });
    tr.parentElement.insertBefore(clone, tr.nextSibling);
  }else if(table.rows.length>1){
    tr.remove();
  }
  if(window._sboxFlush) _sboxFlush();
}
function sboxMerge(){
  var td = sboxCell();
  if(!td || !td.nextElementSibling) return;
  var next = td.nextElementSibling;
  var span = (parseInt(td.getAttribute('colspan')||'1',10)||1)+(parseInt(next.getAttribute('colspan')||'1',10)||1);
  td.setAttribute('colspan', String(span));
  td.innerHTML = (td.innerHTML+' '+next.innerHTML).trim();
  next.remove();
  if(window._sboxFlush) _sboxFlush();
}
function sboxCleanHtml(){
  var clone = document.body.cloneNode(true);
  var r = clone.querySelector('#sbox-ruler');
  if(r) r.remove();
  return clone.innerHTML;
}
var _sboxHist = [];
var _sboxHistI = -1;
var _sboxSnapLock = false;
function sboxSnap(){
  if(_sboxSnapLock) return;
  var html = document.body.innerHTML;
  if(_sboxHist[_sboxHistI]===html) return;
  _sboxHist = _sboxHist.slice(0, _sboxHistI+1);
  _sboxHist.push(html);
  if(_sboxHist.length>60){ _sboxHist.shift(); }
  _sboxHistI = _sboxHist.length-1;
}
function sboxUndo(){
  if(_sboxHistI<=0) return;
  _sboxHistI--;
  _sboxSnapLock = true;
  document.body.innerHTML = _sboxHist[_sboxHistI];
  _sboxSnapLock = false;
  if(window._sboxFlush) _sboxFlush();
  sboxPlaceCaret();
}
function sboxRedo(){
  if(_sboxHistI>=_sboxHist.length-1) return;
  _sboxHistI++;
  _sboxSnapLock = true;
  document.body.innerHTML = _sboxHist[_sboxHistI];
  _sboxSnapLock = false;
  if(window._sboxFlush) _sboxFlush();
  sboxPlaceCaret();
}
function sboxPlaceCaret(){
  var bar = document.getElementById('sbox-ruler');
  if(!bar) return;
  var sel = window.getSelection();
  if(!sel || sel.rangeCount===0) return;
  var r = sel.getRangeAt(0).cloneRange();
  r.collapse(true);
  var rect = r.getClientRects()[0];
  if(!rect) return;
  var mark = document.getElementById('sbox-caret');
  if(!mark) return;
  var host = bar.getBoundingClientRect();
  mark.style.left = Math.max(0, rect.left-host.left)+'px';
}
function sboxNudgeBlock(dx){
  var el = sboxBlock();
  if(!el || el===document.body) return;
  var cur = parseFloat(el.style.marginLeft)||0;
  el.style.marginLeft = Math.max(0, cur+dx)+'px';
  if(window._sboxFlush) _sboxFlush();
}
''';
