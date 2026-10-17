// @author Florent HAZARD <f.hazard@sowapps.com>
import { esc } from './format.js';
import { toast } from './refresh.js';

// ===== Design system : Dialog reutilisable (modales in-app) =====
// HDS.open(opts) -> Promise(valeur du bouton clique)
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
    // `html` est reserve a du contenu que NOUS composons (les libelles venant du
    // serveur y sont echappes par esc()). `body` reste du texte brut, jamais interprete.
    const alerte = opts.alerte
      ? '<div class="hds-alerte '+(opts.alerteNiveau||'warn')+'"><span class="ic">!</span><span>'+esc(opts.alerte)+'</span></div>'
      : '';
    if(opts.html!==undefined){ elBody.innerHTML = alerte + opts.html; }
    else if(alerte){ const t=document.createElement('div'); t.textContent=opts.body||'';
                     elBody.innerHTML = alerte; elBody.appendChild(t); }
    else { elBody.textContent = opts.body||''; }
    // `large` : la popin s'élargit pour ce qui porte un tableau, sans changer le reste.
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
  // Fermer UNIQUEMENT si l'appui ET le relachement ont eu lieu sur le voile : un clic
  // entame dans la fenetre (selection de texte...) et relache dehors declenchait
  // 'click' sur l'ancetre commun -- le voile -- et fermait la popin (constate).
  let appuiSurVoile=false;
  back.addEventListener('mousedown',e=>{ appuiSurVoile=(e.target===back); });
  back.addEventListener('mouseup',e=>{
    if(appuiSurVoile && e.target===back) settle(cancelValue);
    appuiSurVoile=false;
  });
  elX.addEventListener('click',()=>settle(cancelValue));
  // Fenetre de CHOIX : une case a cocher par element, resultat = tableau d'identifiants
  // retenus, ou null si l'utilisateur annule. Rien n'est preselectionne par defaut quand
  // `tousCoches` est faux : une action qui installe ne doit pas partir sur un choix subi.
  // Fenetre de CHOIX : une case a cocher par element, resultat = tableau d'identifiants
  // retenus, ou null si l'utilisateur annule.
  //
  // Elle s'ouvre IMMEDIATEMENT. Si les elements doivent etre charges (`charger`), la
  // fenetre affiche un chargeur et garde son bouton de validation desactive, puis se
  // remplit. Attendre le serveur AVANT d'ouvrir donnait un clic sans reaction visible :
  // l'utilisateur ne savait pas si son clic avait ete pris.
  function choose(opts){
    opts=opts||{};
    let cocheDefaut = opts.tousCoches!==false;
    let items = opts.items || [];

    // Liste VERROUILLEE (`verrouille`) : la source ne sait pas traiter un element en
    // particulier. On montre quand meme la liste -- elle informe -- mais les cases sont
    // cochees et NON decochables, et l'intro dit pourquoi. Laisser decocher un choix qui
    // serait ensuite ignore serait un mensonge d'interface.
    let lock = false;
    // EXCLURE un element depuis la liste (`opts.exclure`) : la fenetre qui montre les
    // mises a jour est exactement l'endroit ou l'on decide qu'un paquet ne doit plus
    // etre propose. Sans cela il fallait retenir son identifiant et aller le taper dans
    // les parametres -- exigence utilisateur.
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
        return '<details class="acc hds-grp" open><summary class="acc-h hds-grp-h" onclick="panel.onGroupHeadClick(event,this)">'
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
    // L'ETAT D'UN GROUPE SE DEDUIT DE SES LIGNES, jamais l'inverse : cocher une ligne a la
    // main doit se voir en haut, et le troisieme etat -- ni tout, ni rien -- est le seul
    // qui dise la verite sur une selection partielle.
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
      // Liste figee : la case reste ACTIVE (une case `disabled` est grisee par le
      // navigateur, on ne verrait plus qu'elle est cochee). L'interaction est coupee par
      // le CSS ; ce filet garantit qu'aucune ne peut se retrouver decochee.
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
        // Un clic sur la case NE PLIE PAS le groupe : sans cela, cocher un constructeur
        // refermait ce qu'on venait d'ouvrir pour le regarder.
        g.addEventListener('click',e=>e.stopPropagation());
        g.addEventListener('change',()=>{
          const block = g.closest('.hds-grp');
          if(block) block.querySelectorAll('input[type=checkbox]:not([data-groupe])')
                       .forEach(b=>{ b.checked = g.checked; });
          maj();
        });
      });
      // « Ignorer » : l'element sort de la liste ET du perimetre, durablement. On attend
      // que l'enregistrement ait REUSSI avant de retirer la ligne : sinon l'utilisateur
      // croirait avoir exclu un paquet qui reviendrait au prochain passage.
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
      // Le bouton reste desactive tant qu'il n'y a rien a valider.
      const v=valider(); if(v) v.disabled=true;
      opts.charger().then(res=>{
        if(stopWaitNotice){ stopWaitNotice(); stopWaitNotice = null; }
        items = (res && res.items) || [];
        lock = !!(res && res.verrouille);
        // Le serveur peut trancher le precochage (reglage utilisateur, D57).
        if(res && res.tousCoches!==undefined) cocheDefaut = !!res.tousCoches;
        const intro = (res && res.intro) || opts.intro;
        // Le libelle du bouton n'est connu qu'apres lecture (« Installer » pour Windows
        // Update, « Mettre a jour » pour un gestionnaire de paquets) : la fenetre, elle,
        // s'ouvre AVANT. On le corrige a l'arrivee de la liste.
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
// Listes de choix deja obtenues, par action+module. Une fenetre de choix ne redemande au
// serveur QUE si son information locale a vieilli : rouvrir la meme fenetre dans la foulee
// ne doit pas relancer une lecture.
