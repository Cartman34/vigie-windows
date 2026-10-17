// @author Florent HAZARD <f.hazard@sowapps.com>
import { esc } from './format.js';
import { toast } from './refresh.js';

// ===== Design system : Dialog reutilisable (modales in-app) =====
// HDS.open(opts) -> Promise(value of the button clicked)
// HDS.confirm({title,body,confirmLabel,cancelLabel,danger}) -> Promise(bool)
// HDS.info(title, body) -> Promise (bouton Fermer)
export const HDS = (function(){
  const back=document.getElementById('hdsBack');
  const dlg=back.querySelector('.hds-dialog');
  const elTitle=document.getElementById('hdsTitle');
  const elBody=document.getElementById('hdsBody');
  const elFoot=document.getElementById('hdsFoot');
  const elIc=document.getElementById('hdsIc');
  const elX=document.getElementById('hdsX');
  const ICON={info:'i',warn:'!',danger:'!'};
  let resolver=null, lastFocus=null, cancelValue=null;

  function settle(v){
    if(!resolver) return;
    back.classList.remove('haut');
    const r=resolver; resolver=null;
    back.classList.remove('show');
    document.removeEventListener('keydown',onKey,true);
    if(lastFocus&&lastFocus.focus){ try{lastFocus.focus();}catch(e){} }
    r(v);
  }
  function onKey(e){
    if(e.key==='Escape'){ e.preventDefault(); settle(cancelValue); }
    else if(e.key==='Enter'){ const b=elFoot.querySelector('[data-default]'); if(b){ e.preventDefault(); b.click(); } }
    else if(e.key==='Tab'){
      const f=dlg.querySelectorAll('button'); if(!f.length) return;
      const first=f[0], last=f[f.length-1];
      if(e.shiftKey&&document.activeElement===first){ e.preventDefault(); last.focus(); }
      else if(!e.shiftKey&&document.activeElement===last){ e.preventDefault(); first.focus(); }
    }
  }
  function open(opts){
    opts=opts||{};
    const variant=opts.variant||'info';
    cancelValue=('cancelValue' in opts)?opts.cancelValue:null;
    elTitle.textContent=opts.title||'';
    // `html` is reserved for content WE compose (labels coming from the server are escaped
    // through esc()). `body` stays plain text, never interpreted.
    const alerte = opts.alerte
      ? '<div class="hds-alerte '+(opts.alerteNiveau||'warn')+'"><span class="ic">!</span><span>'+esc(opts.alerte)+'</span></div>'
      : '';
    if(opts.html!==undefined){ elBody.innerHTML = alerte + opts.html; }
    else if(alerte){ const t=document.createElement('div'); t.textContent=opts.body||'';
                     elBody.innerHTML = alerte; elBody.appendChild(t); }
    else { elBody.textContent = opts.body||''; }
    // `large`: the popup widens for whatever carries a table, without changing the rest.
    dlg.className='hds-dialog hds-dialog--'+variant+(opts.large?' hds-dialog--large':'')+(opts.icon===false?'':' has-ic');
    back.classList.toggle('haut', opts.placement==='haut');
    elIc.textContent=ICON[variant]||'i';
    elX.style.display=(opts.dismissable===false)?'none':'';
    elFoot.innerHTML='';
    const actions=opts.actions||[{label:'Fermer',kind:'primary',value:true,default:true}];
    actions.forEach(a=>{
      const b=document.createElement('button');
      b.className='hds-btn'+(a.kind?(' hds-btn--'+a.kind):'');
      b.textContent=a.label;
      if(a.default) b.setAttribute('data-default','1');
      b.onclick=()=>settle('value' in a?a.value:true);
      elFoot.appendChild(b);
    });
    lastFocus=document.activeElement;
    back.classList.add('show');
    document.addEventListener('keydown',onKey,true);
    const def=elFoot.querySelector('[data-default]')||elFoot.querySelector('button');
    if(def) setTimeout(()=>{ try{def.focus();}catch(e){} },0);
    return new Promise(res=>{ resolver=res; });
  }
  function info(title, body, opts){
    opts=opts||{};
    return open({ title, body, variant:opts.variant||'info',
      actions:[{label:opts.okLabel||'Fermer',kind:'primary',value:true,default:true}] });
  }
  function confirm(opts){
    opts=opts||{};
    const danger=!!opts.danger;
    return open({ title:opts.title||'Confirmer', body:opts.body||'', html:opts.html,
      variant:danger?'danger':'warn', cancelValue:false,
      placement:opts.placement, alerte:opts.alerte, alerteNiveau:opts.alerteNiveau,
      actions:[
        {label:opts.cancelLabel||'Annuler',kind:'ghost',value:false},
        {label:opts.confirmLabel||'Confirmer',kind:danger?'danger':'primary',value:true,default:true}
      ]});
  }
  // Close ONLY if the press AND the release happened on the veil: a click started inside
  // the window (selecting text, say) and released outside fired 'click' on the common
  // ancestor -- the veil -- and closed the popup (seen).
  let appuiSurVoile=false;
  back.addEventListener('mousedown',e=>{ appuiSurVoile=(e.target===back); });
  back.addEventListener('mouseup',e=>{
    if(appuiSurVoile && e.target===back) settle(cancelValue);
    appuiSurVoile=false;
  });
  elX.addEventListener('click',()=>settle(cancelValue));
  // A CHOICE window: one tick box per item, result = an array of the identifiers kept, or
  // null if the user cancels. Nothing is pre-ticked by default when `tousCoches` is false:
  // an action that installs must not start on a choice the user never made.
  // The window opens IMMEDIATELY. If the items have to be fetched (`charger`), it shows a
  // loader and keeps its confirm button disabled, then fills up.
  //
  // Waiting for the server BEFORE opening gave a click with no visible reaction: the user
  // could not tell whether the click had been taken. An interface that takes a gesture
  // says so at once, even when it has nothing to show yet -- the loader IS the answer to
  // the click.
  function choose(opts){
    opts=opts||{};
    let cocheDefaut = opts.tousCoches!==false;
    let items = opts.items || [];

    // A LOCKED list (`verrouille`): the source cannot deal with one item in particular. We
    // still show the list -- it informs -- but the boxes are ticked and CANNOT be
    // unticked, and the intro says why. Letting someone untick a choice that would then be
    // ignored would be an interface telling a lie.
    let lock = false;
    // EXCLUDING an item from the list (`opts.exclure`): the window that shows the updates
    // is exactly the place where one decides that a package must no longer be offered.
    // Without it one had to remember its identifier and go and type it into the settings
    // -- the owner asked for this.
    const rowOf = it =>
      '<div class="hds-choice-row"><label class="hds-choice'+(lock?' hds-choice--fige':'')+'"><input type="checkbox" value="'+esc(it.id)+'"'+((lock||cocheDefaut)?' checked':'')+(lock?' tabindex="-1"':'')+'>'
      + '<span class="hds-choice-t">'+esc(it.title)+'</span>'
      + (it.detail?'<span class="hds-choice-d">'+esc(it.detail)+'</span>':'')
      + '</label>'
      + (opts.exclure ? '<button type="button" class="hds-exclu" data-exclu="'+esc(it.id)+'" title="Ne plus proposer cette mise à jour">Ignorer</button>' : '')
      + '</div>';
    const barre = () => lock ? '' :
      '<div class="hds-choice-bar"><button type="button" class="hds-lnk" id="hdsAll" title="Sélectionner toutes les lignes de la liste">Tout cocher</button>'
      + '<button type="button" class="hds-lnk" id="hdsNone" title="Désélectionner toutes les lignes de la liste">Tout décocher</button>'
      + '<span class="hds-count" id="hdsCount"></span></div>';
    const groupWeight = liste => {
      const sum = liste.reduce((t,x)=>t+(Number(x.bytes)||0),0);
      return sum ? ' · '+octets(sum) : '';
    };
    const render = liste => {
      if(!liste.some(x=>x.group)) return liste.map(rowOf).join('');
      const byGroup = new Map();
      liste.forEach(x=>{ const g = x.group || '—'; if(!byGroup.has(g)) byGroup.set(g,[]); byGroup.get(g).push(x); });
      // Windows first -- it carries the security fix -- then makers alphabetically. An
      // order by volume would reshuffle at every scan.
      //
      // GROUPS OPEN. Grouping was asked for, folding was not: collapsing them by default
      // was my decision and it HID the list the owner wanted to read (10/09). The header
      // carries the count and the weight either way, and a group closes on a click.
      const names = [...byGroup.keys()].sort((a,b)=>
        (a==='Windows'?0:1)-(b==='Windows'?0:1) || a.localeCompare(b,'fr'));
      return names.map(name=>{
        const inside = byGroup.get(name);
        return '<details class="acc hds-grp" open><summary class="acc-h hds-grp-h" data-act="group-head">'
          + '<span class="acc-fl" title="Replier ou déplier ce groupe">&#9654;</span>'
          + '<input type="checkbox" data-groupe="'+esc(name)+'" title="Cocher ou décocher tout ce groupe">'
          + '<span class="hds-grp-n" title="Cocher ou décocher tout ce groupe">'+esc(name)+'</span>'
          + '<span class="hds-grp-fill" title="Replier ou déplier ce groupe"></span>'
          + '<span class="hds-grp-c" title="Replier ou déplier ce groupe">'+inside.length+groupWeight(inside)+'</span>'
          + '</summary><div class="acc-b hds-grp-b">'+inside.map(rowOf).join('')+'</div></details>';
      }).join('');
    };
    const corps = (intro, dedans) =>
      (intro ? '<p class="hds-intro">'+esc(intro)+'</p>' : '') + barre() + '<div class="hds-choices">'+dedans+'</div>';
    // A WAIT SAYS WHAT IT WAITS FOR, AND FOR HOW LONG (S32). On 16/10 this sentence stayed on screen for
    // minutes while the server was stuck: motionless, it tells a computation under way from a breakdown in no
    // way at all. The counter starts again at every opening, and past a threshold the sentence says what to do.
    const chargeur = '<div class="hds-loading" id="hdsWait"><span class="spin"></span> <span id="hdsWaitText">Lecture en cours…</span></div>';
    const startWaitNotice = (quoi) => {
      const debut = Date.now();
      const tic = setInterval(() => {
        const el = document.getElementById('hdsWaitText');
        if (!el) { clearInterval(tic); return; }
        const s = Math.round((Date.now() - debut) / 1000);
        if (s < 3) return;
        el.textContent = (s < 20)
          ? quoi + ' — ' + s + ' s'
          : quoi + ' — ' + s + ' s. Le serveur ne répond pas encore ; la carte Vigie dit ce qu\'il fait.';
      }, 1000);
      return () => clearInterval(tic);
    };

    const p = open({ title:opts.title||'Choisir',
      html: corps(opts.intro, opts.charger ? chargeur : render(items)),
      variant:opts.variant||'info', cancelValue:null,
      actions:[ {label:opts.cancelLabel||'Annuler',kind:'ghost',value:null},
                {label:opts.confirmLabel||'Valider',kind:'primary',value:'__ok__',default:true} ] });

    const boites=()=>[...elBody.querySelectorAll('input[type=checkbox]:not([data-groupe])')];
    const groupBoxes=()=>[...elBody.querySelectorAll('input[data-groupe]')];
    // A GROUP'S STATE IS DEDUCED FROM ITS ROWS, never the other way round: ticking a row
    // by hand must show at the top, and the third state -- neither all nor none -- is the
    // only one that tells the truth about a partial selection.
    const refreshGroups=()=>{
      groupBoxes().forEach(g=>{
        const block = g.closest('.hds-grp');
        const inside = block ? [...block.querySelectorAll('input[type=checkbox]:not([data-groupe])')] : [];
        const ticked = inside.filter(b=>b.checked).length;
        g.checked = inside.length>0 && ticked===inside.length;
        g.indeterminate = ticked>0 && ticked<inside.length;
      });
    };
    const valider=()=>elFoot.querySelector('[data-default]');
    let retenus=[];
    const maj=()=>{
      // A frozen list: the box stays ACTIVE (a `disabled` box is greyed by the browser,
      // and one could no longer see that it is ticked). The interaction is cut by the CSS;
      // this net makes sure none can end up unticked.
      if(lock) boites().forEach(b=>{ b.checked = true; });
      retenus = boites().filter(b=>b.checked).map(b=>b.value);
      refreshGroups();
      const c=elBody.querySelector('#hdsCount');
      if(c) c.textContent = items.length ? (retenus.length+' / '+items.length+L('ui.selectionnee')) : '';
      const v=valider(); if(v) v.disabled = (retenus.length===0);
    };
    const brancher=()=>{
      const a=elBody.querySelector('#hdsAll'), n=elBody.querySelector('#hdsNone');
      if(a) a.onclick=()=>{ boites().forEach(b=>b.checked=true); maj(); };
      if(n) n.onclick=()=>{ boites().forEach(b=>b.checked=false); maj(); };
      boites().forEach(b=>b.addEventListener('change',maj));
      groupBoxes().forEach(g=>{
        // A click on the box DOES NOT FOLD the group: without this, ticking a vendor
        // closed again what one had just opened to look at.
        g.addEventListener('click',e=>e.stopPropagation());
        g.addEventListener('change',()=>{
          const block = g.closest('.hds-grp');
          if(block) block.querySelectorAll('input[type=checkbox]:not([data-groupe])')
                       .forEach(b=>{ b.checked = g.checked; });
          maj();
        });
      });
      // "Ignore": the item leaves the list AND the scope, for good. We wait for the save
      // to have SUCCEEDED before removing the row: otherwise the user would believe they
      // had excluded a package that would come back on the next pass.
      elBody.querySelectorAll('[data-exclu]').forEach(b=>{ b.onclick=async()=>{
        const id=b.getAttribute('data-exclu');
        b.disabled=true; b.textContent='…';
        try{
          await opts.exclure(id);
          const rangee=b.closest('.hds-choice-row');
          items = items.filter(x=>String(x.id)!==String(id));
          if(rangee) rangee.remove();
          if(!items.length){
            const z=elBody.querySelector('.hds-choices');
            if(z) z.innerHTML='<p class="hds-intro">Plus rien à proposer : tout est ignoré.</p>';
          }
          maj();
        }catch(e){
          b.disabled=false; b.textContent='Ignorer';
          toast(L('ui.impossible-ignorer')+(e.message||e));
        }
      }; });
      maj();
    };
    brancher();

    let stopWaitNotice = null;
    if(opts.charger){
      stopWaitNotice = startWaitNotice('Lecture de la liste');
      // The button stays disabled as long as there is nothing to confirm.
      const v=valider(); if(v) v.disabled=true;
      opts.charger().then(res=>{
        if(stopWaitNotice){ stopWaitNotice(); stopWaitNotice = null; }
        items = (res && res.items) || [];
        lock = !!(res && res.verrouille);
        // The server may settle the pre-ticking (a user setting, D57).
        if(res && res.tousCoches!==undefined) cocheDefaut = !!res.tousCoches;
        const intro = (res && res.intro) || opts.intro;
        // The button's label is only known after reading ("Install" for Windows Update,
        // "Update" for a package manager): the window itself opens BEFORE. We correct it
        // when the list arrives.
        const lib = res && res.confirmLabel;
        if(lib){ const b=valider(); if(b) b.textContent = lib; }
        if(!items.length){
          elBody.innerHTML = '<p class="hds-intro">'+esc((res && res.empty) || L('ui.rien-afficher'))+'</p>';
          return;
        }
        elBody.innerHTML = corps(intro, render(items));
        brancher();
      }).catch(e=>{
        elBody.innerHTML = '<p class="hds-intro">Lecture impossible : '+esc(e.message||String(e))+'</p>';
      });
    }
    return p.then(v => v==='__ok__' ? retenus : null);
  }

  return { open, info, confirm, choose, close:()=>settle(cancelValue) };
})();

// Compat : anciens appels -> HDS
function closeModal(){ HDS.close(); }
export function setBtnBusy(btn){
  if(!btn||btn.dataset.busy) return;
  btn.dataset.busy='1';
  btn.dataset.prevHtml=btn.innerHTML;
  btn.style.minWidth=btn.offsetWidth+'px';
  btn.disabled=true; btn.classList.add('busy');
  btn.innerHTML='<span class="spin"></span>En cours…';
}
export function clearBtnBusy(btn){
  if(!btn||!btn.dataset.busy) return;
  btn.innerHTML=btn.dataset.prevHtml;
  btn.disabled=false; btn.classList.remove('busy');
  btn.style.minWidth='';
  delete btn.dataset.busy; delete btn.dataset.prevHtml;
}
export function octets(n){
  n=+n||0; if(!n) return '';
  const u=['o','Ko','Mo','Go']; let i=0;
  while(n>=1024 && i<u.length-1){ n/=1024; i++; }
  return (i?n.toFixed(1):n)+' '+u[i];
}
// Choice lists already obtained, by action plus module. A choice window only asks the
// server again if its local information has aged: reopening the same window straight away
// must not start another read.
