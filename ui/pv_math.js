'use strict';
(function(){
 const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 window.PVMath={html(tex,display=true){
  if(!window.katex)return '<code>'+escape(tex)+'</code>';
  return katex.renderToString(tex,{displayMode:display,throwOnError:true,trust:false,strict:'error',output:'htmlAndMathml'});
 },render(root=document){root.querySelectorAll('[data-tex]').forEach(node=>{node.innerHTML=this.html(node.dataset.tex,node.dataset.inline!=='true');});}};
})();
