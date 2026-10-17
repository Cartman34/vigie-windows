// @author Florent HAZARD <f.hazard@sowapps.com>
import { octets } from './dialog.js';
import { att, esc } from './format.js';

function progressHtml(f){
  const p=f.progress; if(!p||!p.phase) return '';
  const pct=v=>(typeof v==='number'&&isFinite(v))?Math.max(0,Math.min(100,Math.round(v))):null;
  const duration=s=>s>=60?(Math.floor(s/60)+' min '+String(s%60).padStart(2,'0')+' s'):(s+' s');
  const secondsSince=d=>d?Math.max(0,Math.round((Date.now()-new Date(d).getTime())/1000)):null;
  const g=pct(p.percent), it=pct(p.itemPercent);
  const items=Array.isArray(p.items)?p.items:[];
  const current=items.find(x=>x&&x.state==='en cours')||null;
  const failures=items.filter(x=>x&&(x.state==='échec'||x.state==='annulée'));
  const idle=secondsSince(p.lastChange);
  const stalled=idle!==null&&idle>=120;
  const bytesText=(p.bytesTotal>0)?(octets(p.bytesDone||0)+' sur '+octets(p.bytesTotal)):'';
  const currentTitle=(current&&current.title)||p.title||'';
  let html='<div class="fprog">';
  // 1. The current item.
  if(currentTitle){
    html+='<div class="fprog-current"><div class="fprog-title" title="'+att(currentTitle)+'">'+esc(currentTitle)+'</div>'
      +'<div class="fprog-line"><span>'+esc(p.activity||p.phase)+(bytesText?' · '+esc(bytesText):'')+'</span><span>'+(it!==null?it+' %':'')+'</span></div>'
      +(it!==null?'<div class="fprog-bar"><span style="width:'+it+'%"></span></div>':'')+'</div>';
  }
  if(stalled) html+='<div class="fprog-alert warn">Aucun progrès depuis '+esc(duration(idle))+' : Windows Update peut attendre une autre installation ou le réseau.</div>';
  if(failures.length) html+='<div class="fprog-alert error">'+failures.length+' mise(s) à jour en échec : '+esc(failures.map(x=>x.title+(x.code?' ('+x.code+')':'')).join(' ; '))+'</div>';
  // 2. Every item, with its state: the current one first, then the failures, then the waiting ones. The successful ones
  //    fold behind a button, so that forty updates do not stretch the card.
  if(items.length){
    const rankOf=x=>{ const s=String((x&&x.state)||''); return s==='en cours'?0:((s==='échec'||s==='annulée')?1:(s==='en attente'?2:3)); };
    const row=x=>{
      const state=String((x&&x.state)||'');
      const cls=(state==='échec'||state==='annulée')?'error':(state==='en cours'?'run':((state==='en attente')?'wait':'done'));
      const stateText=state+(x.percent!=null&&state==='en cours'?' · '+pct(x.percent)+' %':'')+(x.code?' · '+x.code:'');
      return '<li class="'+cls+'"><span class="fprog-dot"></span><span class="fprog-name" title="'+att(x.title||'')+'">'+esc(x.title||'')+'</span><span class="fprog-state">'+esc(stateText)+'</span></li>';
    };
    const pending=items.filter(x=>rankOf(x)<3).sort((a,b)=>rankOf(a)-rankOf(b));
    const succeeded=items.filter(x=>rankOf(x)===3);
    if(pending.length) html+='<ul class="fprog-items">'+pending.map(row).join('')+'</ul>';
    if(succeeded.length){
      const open=progressDoneOpen.has(f.key);
      html+='<button type="button" class="fprog-more" data-n="'+succeeded.length+'" onclick="panel.toggleProgressDone(this,\''+att(f.key)+'\')">'
        +(open?'Masquer ':'Afficher ')+succeeded.length+' mise(s) à jour réussie(s)</button>'
        +'<ul class="fprog-items succeeded"'+(open?'':' hidden')+'>'+succeeded.map(row).join('')+'</ul>';
    }
  }
  // 3. The overall progress, at the bottom.
  const rank=(p.index&&p.total)?(' · '+p.index+' sur '+p.total):'';
  const elapsed=secondsSince(p.since);
  html+='<div class="fprog-total"><div class="fprog-line"><span>'+esc(p.phase)+esc(rank)+(elapsed!==null?' · depuis '+esc(duration(elapsed)):'')+'</span><span>'+(g!==null?g+' %':'')+'</span></div>'
    +(g!==null?'<div class="fprog-bar total"><span style="width:'+g+'%"></span></div>':'')+'</div>';
  return html+'</div>';
}// THE FOLDED SUCCESSFUL UPDATES STAY OPEN ACROSS REFRESHES: the card is redrawn every few seconds, and a list that closes
// itself under the reader's eyes would have to be reopened each time.
const progressDoneOpen=new Set();
export function toggleProgressDone(btn,key){
  const list=btn.nextElementSibling; if(!list) return;
  const open=list.hidden;
  list.hidden=!open;
  if(open) progressDoneOpen.add(key); else progressDoneOpen.delete(key);
  btn.textContent=(open?'Masquer ':'Afficher ')+btn.dataset.n+' mise(s) à jour réussie(s)';
}
/* L'EN-TETE D'UN GROUPE FAIT DEUX CHOSES, ET CHAQUE ZONE DIT LAQUELLE.

   Tout clic sur un <summary> replie : la case et le nom du groupe repliaient donc au lieu de cocher, alors que
   les lignes en dessous sont des <label> ou le texte coche. Signale le 20/09. Le nom et la case cochent ; la
   fleche, le vide qui suit le nom et le compte replient. Le pli natif est annule pour ces deux zones seulement,
   et la bascule de la case est alors faite a la main -- annuler le geste par defaut annule aussi son cochage.
   Le clavier ne perd rien : Entree sur l'en-tete replie, Tab puis Espace cochent. */
/* L'ACCORDEON : UNE SEULE MISE EN OEUVRE POUR TOUTE L'APPLICATION.

   Un <details> ne s'anime pas : il montre ou il cache. La hauteur du corps est donc animee ici, a l'ouverture
   comme a la fermeture, et l'element ne se referme qu'une fois l'animation finie. Tout <details class="acc">
   en profite sans une ligne de plus : la delegation attrape le clic sur son en-tete. Qui a besoin d'un
   accordeon demain pose les trois classes -- acc, acc-h, acc-b -- et n'ecrit rien.

   Le reglage « animations reduites » de Windows est respecte : le pli devient instantane. */
