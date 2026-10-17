// @author Florent HAZARD <f.hazard@sowapps.com>
import { REPO_URL } from './config.js';
import { API, TOKEN } from './api.js';
import { refreshCard } from './card-refresh.js';
import { lastHost, lastModules, lastUnits } from './cards.js';
import { UI } from './components.js';
import { esc } from './format.js';
import { refresh, toast, toggleTheme } from './refresh.js';
import { clearPendingUnitFocus, getNotifCfg, pendingUnitFocus, postNotif, renderSettings, toggleSettings, unitsOpen } from './settings.js';
import { wireRepoLinks } from './shell.js';

export async function renderTabModules(pane){
  const units=lastUnits||[];
  if(!units.length){ pane.innerHTML='<div class="drawer-empty">Aucun module connu (maquette&nbsp;?).</div>'; return; }
  let paramCat={};
  try{
    const r=await fetch(API+"/parameters",{headers:{Authorization:"Bearer "+TOKEN}});
    if(r.ok){ const j=await r.json(); (j.modules||[]).forEach(m=>{ paramCat[m.unit]=m.params||[]; }); }
  }catch(e){}
  const cfg=await getNotifCfg();
  const notifCat=cfg.catalog||[];
  const on=id=> (id in cfg.modules)? !!cfg.modules[id] : true;
  pane.innerHTML='<p class="um-hint">Couper un module retire ses cartes et ses calculs ; il reste listé ici pour être rallumé. Dépliez-en un pour régler <b>ses notifications</b> et <b>ses paramètres</b>.</p>'+units.map(u=>{
    const cards=(lastModules||[]).filter(m=>m.theme===u.id);
    // NOTIFICATIONS : les evenements que le module sait signaler, avec leur vrai nom
    // (« Temperature GPU elevee »), pas le nom des cartes -- exigence utilisateur.
    const decl=((notifCat||[]).find(x=>x.unit===u.id)||{}).notifications||[];
    const onNotif=(unit,key)=>{ const r=unit+'.'+key; return (cfg.notifs && (r in cfg.notifs)) ? !!cfg.notifs[r] : on(unit); };
    // Qui peut agir : une notification « admin » ne derange pas un compte standard,
    // sauf si elle est critique -- alors elle remonte quand meme, en invitant a
    // prevenir un administrateur.
    const etiquettesNotif=nn=>[].concat(nn.rights==='admin'?['admin']:[], nn.critical?['critique']:[]);
    const fieldCount=(decl.length
      ? UI.bande('Notifications', decl.length)
        + UI.liste(decl.map(nn=>UI.ligne({
            libelle: nn.label, aide: nn.help||'', etiquettes: etiquettesNotif(nn),
            droite: UI.interrupteur('data-unotif="'+esc(u.id)+'::'+esc(nn.key)+'"', onNotif(u.id,nn.key))
          })))
      : UI.bande('Notifications') + UI.note(L('ui.ce-module-ne-signale')));
    // ACCORDEON, coherent avec le reste de l'app (l'arbre du disque et les details de
    // champ se deplient deja ainsi ; les onglets, eux, sont deja pris par la navigation
    // des Parametres). Tout est replie : la liste des modules se lit d'un coup d'oeil,
    // et on ouvre celui qu'on veut regler.
    const targetIndex=(pendingUnitFocus===u.id);
    return '<details class="um'+(u.enabled?'':' off')+'" id="um-'+esc(u.id)+'"'+(targetIndex?' open':'')+'>'
      +'<summary class="um-head"><div class="um-t"><b>'+esc(u.label)+'</b><small>'+esc(u.description||'')+'</small></div>'
      +'<span class="um-sw"><span>'+(u.enabled?'Actif':L('ui.coupe'))+'</span>'
      +UI.interrupteur('data-unit="'+esc(u.id)+'"', u.enabled)+'</span></summary>'
      +(u.enabled ? fieldCount : '<div class="um-note">Module coupé : ses cartes ne sont ni calculées ni affichées.</div>')
      +(u.enabled && (paramCat[u.id]||[]).filter(pr=>pr.type!=='list').length ? UI.bande(L('ui.parametres'), (paramCat[u.id]||[]).filter(pr=>pr.type!=='list').length)+'<div class="um-list">'+(paramCat[u.id]||[]).filter(pr=>pr.type!=='list').map(pr=>{
        const ref=esc(u.id)+'::'+esc(pr.key);
        const btnDef=pr.overridden?'<button class="um-reset" data-preset="'+ref+L('ui.title-revenir-la-valeur')+esc(Array.isArray(pr.default)?(pr.default.join(', ')||'vide'):String(pr.default))+(pr.unit?' '+esc(pr.unit):'')+')">défaut</button>':'';
        let ctl='';
        if(pr.type==='bool'){
          ctl=UI.interrupteur('data-pval="'+ref+'"', pr.value);
        } else {
          const curseur=(pr.min!=null&&pr.max!=null)
            ? '<input class="um-range" type="range" data-prange="'+ref+'" min="'+pr.min+'" max="'+pr.max+'" step="'+(pr.step||1)+'" value="'+esc(String(pr.value))+'">'
            : '';
          ctl=curseur+'<input class="um-num" type="number" data-pval="'+ref+'"'
            +(pr.min!=null?' min="'+pr.min+'"':'')+(pr.max!=null?' max="'+pr.max+'"':'')
            +' value="'+esc(String(pr.value))+'">'+(pr.unit?'<span>'+esc(pr.unit)+'</span>':'');
        }
        // um-pline : une ligne de parametre porte des commandes plus larges qu'un
        // interrupteur ; la classe ne change que cet espacement.
        return UI.ligneHtml(esc(pr.label), btnDef+ctl, pr.help||'').replace('class="um-card"', 'class="um-card um-pline"');
      }).join('')+'</div>' : '')
      // LISTES : une SECTION dediee par liste (exigence utilisateur). Une ligne de
      // parametre est trop etroite pour lire, ajouter et retirer ; ici la liste prend
      // toute la largeur, chaque element porte sa croix, le champ d'ajout est visible.
      +(u.enabled ? (paramCat[u.id]||[]).filter(pr=>pr.type==='list').map(pr=>{
        const ref=esc(u.id)+'::'+esc(pr.key);
        const items=Array.isArray(pr.value)?pr.value:[];
        return '<div class="um-sub">'+esc(pr.label)+'<span class="um-cpt">'+(items.length?(items.length+' \u00e9l\u00e9ment'+(items.length>1?'s':'')):'vide')+'</span></div>'
          +(pr.help?'<div class="um-note">'+esc(pr.help)+'</div>':'')
          +'<div class="um-liste" data-plist="'+ref+'">'
          +(items.length
             ? items.map(v=>'<div class="um-lrow"><span>'+esc(String(v))+'</span>'
               +'<button class="um-ldel" data-pdel title="Retirer de la liste">×</button></div>').join('')
             : '<div class="um-lvide">Aucun élément.</div>')
          +'<div class="um-ladd"><input class="um-chip-add" type="text" placeholder="ajouter… (Entrée)">'
          +'<button class="um-lplus" data-padd title="Ajouter a la liste">Ajouter</button></div>'
          +'</div>';
      }).join('') : '')
      +'</details>';
  }).join('');
  // L interrupteur vit DANS l en-tete depliante : sans cela, le clic dessus replierait
  // le module au lieu de le couper.
  pane.querySelectorAll('.um-head .swx').forEach(sw=>{ sw.addEventListener('click', e=>{ e.stopPropagation(); }); });
  // Un interrupteur = UNE notification (« module::cle »). Le reglage part dans `notifs`,
  // qui l'emporte sur le reglage du module : couper une notification precise ne coupe pas
  // les autres.
  pane.querySelectorAll('[data-unotif]').forEach(c=>{ c.onchange=async()=>{
    const [unit,key]=c.getAttribute('data-unotif').split('::');
    const notifs={}; notifs[unit+'.'+key]=c.checked;
    try{ await postNotif({notifs}); }
    catch(e){ c.checked=!c.checked; toast(L('ui.reglage-impossible')+(e.message||e)); }
  }; });
  async function postParam(unit, key, inputValue){
    const values={}; values[key]=inputValue;
    const r=await fetch(API+'/parameters/'+encodeURIComponent(unit),{ method:'POST',
      headers:{ Authorization:'Bearer '+TOKEN, 'Content-Type':'application/json' },
      body: JSON.stringify({ values }) });
    if(!r.ok) throw new Error('HTTP '+r.status);
  }
  // Un parametre change ne recalcule QUE les cartes de son module : le serveur a deja
  // invalide leurs sondes, chaque carte se recharge fraiche sans payer les autres.
  async function afterParam(unit){
    // Le panneau d abord (valeur et bouton defaut a jour tout de suite), les cartes
    // ensuite, sans bloquer : chacune se remplace quand son calcul aboutit.
    await renderSettings();
    (lastModules||[]).filter(m=>m.theme===unit).forEach(m=>{ refreshCard(m.id); });
  }
  pane.querySelectorAll('[data-pval]').forEach(c=>{ c.onchange=async()=>{
    const [unit,key]=c.getAttribute('data-pval').split('::');
    const inputValue=(c.type==='checkbox')?c.checked:Number(c.value);
    try{ await postParam(unit,key,inputValue); toast(L('ui.parametre-enregistre')); await afterParam(unit); }
    catch(e){ toast(L('ui.reglage-impossible')+(e.message||e)); }
  }; });
  // Curseur : il suit le champ nombre et reciproquement ; seul le relachement enregistre.
  pane.querySelectorAll('[data-prange]').forEach(r=>{
    const num=pane.querySelector('[data-pval="'+r.getAttribute('data-prange')+'"]');
    r.oninput=()=>{ if(num) num.value=r.value; };
    r.onchange=()=>{ if(num){ num.value=r.value; num.dispatchEvent(new Event('change')); } };
    if(num){ num.addEventListener('input',()=>{ r.value=num.value; }); }
  });
  // Jetons : ajout par Entree, retrait par la croix ; chaque geste enregistre la liste.
  pane.querySelectorAll('[data-plist]').forEach(bloc=>{
    const [unit,key]=bloc.getAttribute('data-plist').split('::');
    const envoyer=async()=>{
      const items=[...block.querySelectorAll('.um-lrow > span')].map(sp=>sp.textContent);
      try{ await postParam(unit,key,items); toast(L('ui.liste-enregistree')); await afterParam(unit); }
      catch(e){ toast(L('ui.reglage-impossible')+(e.message||e)); }
    };
    block.querySelectorAll('[data-pdel]').forEach(b2=>{ b2.onclick=()=>{ b2.closest('.um-lrow').remove(); envoyer(); }; });
    const champ=bloc.querySelector('.um-chip-add');
    const ajouter=()=>{
      const v=(champ.value||'').trim();
      if(!v) return;
      const vide=bloc.querySelector('.um-lvide'); if(vide) vide.remove();
      const rowOf=document.createElement('div'); rowOf.className='um-lrow';
      const txt=document.createElement('span'); txt.textContent=v; rowOf.appendChild(txt);
      const x=document.createElement('button'); x.className='um-ldel'; x.textContent='×';
      x.title=L('ui.retirer-de-la-liste');
      x.onclick=()=>{ rowOf.remove(); envoyer(); };
      rowOf.appendChild(x);
      bloc.insertBefore(rowOf, bloc.querySelector('.um-ladd'));
      champ.value=''; envoyer();
    };
    if(champ){ champ.onkeydown=e=>{ if(e.key==='Enter'){ e.preventDefault(); ajouter(); } }; }
    const plus=bloc.querySelector('[data-padd]'); if(plus){ plus.onclick=ajouter; }
  });
  pane.querySelectorAll('.um-reset').forEach(b=>{ b.onclick=async()=>{
    const [unit,key]=b.getAttribute('data-preset').split('::');
    try{ await postParam(unit,key,null); toast(L('ui.retour-la-valeur-par')); await afterParam(unit); }
    catch(e){ toast(L('ui.reglage-impossible')+(e.message||e)); }
  }; });
  pane.querySelectorAll('[data-unit]').forEach(c=>{ c.onchange=async()=>{
    const id=c.getAttribute('data-unit');
    c.disabled=true;
    try{
      const r=await fetch(API+'/units/'+encodeURIComponent(id),{ method:'POST',
        headers:{ Authorization:'Bearer '+TOKEN, 'Content-Type':'application/json' },
        body: JSON.stringify({ enabled: c.checked }) });
      if(!r.ok) throw new Error('HTTP '+r.status);
      toast(c.checked ? L('ui.module-active-recalcul-en') : L('ui.module-desactive'));
      await refresh();
      renderSettings();
    }catch(e){ c.checked=!c.checked; c.disabled=false; toast(L('ui.changement-impossible')+(e.message||e)); }
  }; });
  if(pendingUnitFocus){
    const el=document.getElementById('um-'+pendingUnitFocus);
    if(el){ el.scrollIntoView({block:'start',behavior:'smooth'}); el.classList.add('flash');
            setTimeout(()=>el.classList.remove('flash'),1400); }
    clearPendingUnitFocus();
  }
}
// --- Onglet Apparence : cartes-radio, pretes a accueillir d autres themes ---
const THEMES=[
  {id:'dark',  nom:L('ui.theme-sombre'), fond:'#0d1117', panneau:'#161b22', texte:'#e6edf3'},
  {id:'light', nom:L('ui.theme-clair'),  fond:'#e9edf4', panneau:'#ffffff', texte:'#1c2230'}
];
// --- Onglet Utilisateurs (D65) : qui, sur cette machine, a Vigie au demarrage ---
// L'ecriture demande un serveur eleve : sinon les interrupteurs restent VISIBLES mais
// inertes, et disent pourquoi (rien ne disparait de l'interface -- D59).
export async function renderTabUtilisateurs(pane){
  pane.innerHTML='<div class="hds-loading"><span class="spin"></span>Lecture des comptes de la machine…</div>';
  let data={users:[],canWrite:false};
  try{
    const r=await fetch(API+'/users',{headers:{Authorization:'Bearer '+TOKEN}});
    if(r.ok) data=await r.json();
  }catch(e){}
  const users=data.users||[];
  const inerte=!data.canWrite;
  // Installation PERSONNELLE (poste de developpement, depot clone) : les autres comptes
  // ne peuvent pas lire l'application. On ne propose alors pas ce qui echouerait.
  const partage=(data.shared!==false);
  pane.innerHTML=
    '<div class="um-sub">Comptes de cet ordinateur</div>'
    +'<ul class="um-points">'
    +'<li>Un compte <b>coché</b> démarre Vigie à son ouverture de session.</li>'
    +'<li>Chacun garde <b>ses</b> réglages, ses notifications et son historique.</li>'
    +"<li>Un compte standard n'obtient <b>aucun droit en plus</b> : Vigie lui refuse les actions administrateur, comme Windows.</li>"
    +'</ul>'
    +(inerte?'<div class="um-note">Modifier ces choix demande un Vigie lancé en administrateur.</div>':'')
    // CE QUE VOIT UNE FENETRE QUI NE DIT PAS QUI ELLE EST. Meme ecran que les comptes :
    // c'est la meme question -- qui a le droit de voir quoi.
    +UI.carte({
        titre:L('ui.fenetre-sans-session'),
        detail:L('ui.fenetre-sans-session-detail'),
        droite:'<select id="anonMode" class="um-select"'+(inerte?' disabled':'')+'>'
              +'<option value="error"'+((data.anonymousAccess!=='cards')?' selected':'')+'>'+L('ui.anon-page-erreur')+'</option>'
              +'<option value="cards"'+((data.anonymousAccess==='cards')?' selected':'')+'>'+L('ui.anon-cartes')+'</option>'
              +'</select>'
      })
    // CET ECRAN CHOISIT DES COMPTES. RIEN D'AUTRE.
    //
    // Il portait aussi un bouton « Deployer pour tous », qui installait Vigie dans
    // Program Files par un chemin a lui : un second geste d'installation, avec son propre
    // comportement a tenir, cache dans l'ecran des comptes. On dit ce qui manque, et on
    // renvoie la ou l'installation se fait -- une seule fois, au meme endroit.
    +(partage?'':UI.carte({
        titre:L('ui.cette-installation-est-lisible'),
        detail: esc(data.installPath||'')+L('ui.les-autres-comptes-ne')
               +L('ui.installer-depuis-la-carte'),
        detailHtml:true
      }))
    +UI.liste(users.map(u=>UI.ligneHtml(
        esc(u.name)
        +(u.current?UI.etiquette('vous'):'')
        +(u.admin?UI.etiquette('administrateur'):'')
        +((u.fullName&&u.fullName!==u.name)?'<br><span class="um-mut">'+esc(u.fullName)+'</span>':''),
        UI.interrupteur('data-user="'+esc(u.name)+'"'+((inerte||(!partage&&!u.current))?' disabled':''), u.enabled)
      )));
  const am=pane.querySelector('#anonMode');
  if(am){ am.onchange=async()=>{
    const previous = (data.anonymousAccess==='cards') ? 'cards' : 'error';
    am.disabled=true;
    try{
      const r=await fetch(API+'/anonymous-access',{ method:'POST',
        headers:{ Authorization:'Bearer '+TOKEN, 'Content-Type':'application/json' },
        body: JSON.stringify({ mode:am.value }) });
      if(!r.ok){ const j=await r.json().catch(()=>({})); throw new Error(j.error||('HTTP '+r.status)); }
      const j=await r.json(); data.anonymousAccess=j.anonymousAccess;
      toast(j.anonymousAccess==='cards' ? L('ui.anon-cartes-confirme') : L('ui.anon-erreur-confirme'));
    }catch(e){ am.value=previous; toast(L('ui.reglage-impossible')+(e.message||e)); }
    am.disabled=false;
  }; }
  pane.querySelectorAll('[data-user]').forEach(c=>{ c.onchange=async()=>{
    const accountName=c.getAttribute('data-user');
    try{
      const r=await fetch(API+'/users/'+encodeURIComponent(accountName),{ method:'POST',
        headers:{ Authorization:'Bearer '+TOKEN, 'Content-Type':'application/json' },
        body: JSON.stringify({enabled:c.checked}) });
      if(!r.ok){ const j=await r.json().catch(()=>({})); throw new Error(j.error||('HTTP '+r.status)); }
      toast(c.checked?(L('ui.vigie-demarrera-avec')+accountName):(L('ui.vigie-ne-demarrera-plus')+accountName));
    }catch(e){ toast(L('ui.impossible')+(e.message||e)); c.checked=!c.checked; }
  }; });
}

export function renderTabApparence(pane){
  const courant = dark ? 'dark' : 'light';
  pane.innerHTML='<p class="um-hint">Le thème s’applique immédiatement. Le bouton rapide reste disponible dans le pied de page.</p>'
    +'<div class="theme-grid">'+THEMES.map(t=>
      '<label class="theme-opt'+(t.id===courant?' on':'')+'">'
      +'<input type="radio" name="setTheme" value="'+t.id+'"'+(t.id===courant?' checked':'')+'>'
      +'<span class="theme-prev" style="background:'+t.fond+'">'
      +'<span class="theme-prev-card" style="background:'+t.panneau+';color:'+t.texte+'">Aa</span></span>'
      +'<span class="theme-nom">'+t.nom+'</span></label>').join('')
    +'</div>'
    // ENTREE DU MODE REORGANISATION (D92). Elle vit ici, dans les Parametres, et non
    // dans l'en-tete : un bouton de plus en haut de page se clique par megarde, et
    // l'en-tete n'accueille aucun bouton epars (D56).
    +UI.carte({
        titre:L('ui.disposition-des-cartes'),
        detail:L('ui.ranger-les-cartes-comme'),
        droite:'<button class="fsolve sev-info" id="btnReorg">Réorganiser</button>'
      });
  const br = pane.querySelector('#btnReorg');
  if(br) br.onclick = () => { if(unitsOpen) toggleSettings(); entrerReorg(); };
  pane.querySelectorAll('[name="setTheme"]').forEach(r=>{ r.onchange=()=>{
    const versSombre = (r.value==='dark');
    if(versSombre!==dark) toggleTheme();
    pane.querySelectorAll('.theme-opt').forEach(o=>o.classList.toggle('on', o.querySelector('input').value===r.value));
  }; });
}
// --- Onglet À propos ---
export function renderTabApropos(pane){
  pane.innerHTML='<div class="um"><b>Vigie</b><p class="um-hint" style="margin:2px 0 10px">Tableau de bord local Windows.</p>'
    +'<div class="apropos-l"><span>Version</span><b>'+esc(window.APP_VERSION&&!window.APP_VERSION.includes('__')?window.APP_VERSION:'—')+'</b></div>'
    +'<div class="apropos-l"><span>Build</span><b>'+esc(window.APP_BUILD&&!window.APP_BUILD.includes('__')?window.APP_BUILD:'—')+'</b></div>'
    +'<div class="apropos-l"><span>Machine</span><b>'+esc(lastHost||'—')+'</b></div>'
    +'<div class="apropos-l"><span>Éditeur</span><b>Sowapps</b></div>'
    +'<div class="apropos-l"><span>Auteur</span><b>Florent HAZARD</b></div>'
    +'<div class="apropos-l"><span>Licence</span><b>MIT</b></div>'
    +'<p style="margin:14px 0 0"><a class="apropos-repo" data-repo-link><svg width="16" height="16" aria-hidden="true"><use href="#ghMark"/></svg><span class="apropos-repo-t"></span></a></p></div>'
    // EXPORTS : deux documents distincts, ouverts dans un onglet et imprimables en PDF
    // depuis le navigateur (D86). Pas de dependance a installer : la page se sert
    // elle-meme des donnees que Vigie possede deja.
    +'<div class="um" style="margin-top:12px"><b>Exports</b>'
    +'<p class="um-hint" style="margin:2px 0 10px">Deux documents à imprimer ou à enregistrer en PDF.</p>'
    +'<p style="display:flex;gap:8px;flex-wrap:wrap;margin:0">'
    +'<a class="apropos-repo" href="/report?type=hardware" target="_blank" rel="noopener">Fiche matérielle</a>'
    +'<a class="apropos-repo" href="/report?type=state" target="_blank" rel="noopener">État actuel</a>'
    +'</p>'
    +'<p class="um-hint" style="margin:10px 0 0">La fiche matérielle liste ce qui ne bouge pas : machine, processeur, mémoire, disques, écrans. L’état actuel est une photo de ce que Vigie voit à l’instant.</p></div>';
  const rl=pane.querySelector('.apropos-repo-t'); if(rl) rl.textContent=REPO_URL.replace(/^https?:[/][/]/,'');
  wireRepoLinks();
}
