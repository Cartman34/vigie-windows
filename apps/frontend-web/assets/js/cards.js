// @author Florent HAZARD <f.hazard@sowapps.com>
import { doAction } from './actions.js';
import { API_MODE, ICONS, openDetails } from './api.js';
import { layoutColumns } from './card-order.js';
import { refreshCard } from './card-refresh.js';
import { openFreshness } from './details.js';
import { STATUS_RANK, att, attributsAction, esc } from './format.js';
import { applyOperationLock, opsByCard } from './operation-lock.js';
import { armerGlisser, modeReorg } from './reorder.js';
import { openSettings } from './settings.js';
import { setMachineName } from './shell.js';

// The field index, for remediation: filled while drawing a card, read again when a detail is opened.
export let fieldsByKey = {};
export let themeLabels={};
export let lastModules=[];
export let lastStateReadAt='';
export let lastUnits=[], lastHost='';
// Persistes : un rechargement (frequent, l'app se recharge a chaque build) ne doit
// pas rendre les groupes que l'utilisateur a masques.
export let hiddenThemes=new Set();
try{ hiddenThemes=new Set(JSON.parse(localStorage.getItem('vigie.hiddenThemes')||'[]')); }catch(e){}
function applyFilter(){
  document.querySelectorAll('.masonry .card[data-theme]').forEach(c=>{
    c.style.display = hiddenThemes.has(c.dataset.theme) ? 'none' : '';
  });
  // ET ON REDISTRIBUE. Masquer une carte la sort de l'affichage, pas de sa colonne : en
  // decochant un groupe on laissait des colonnes vides et un trou au milieu de la grille
  // (constate le 01/09). Les cartes visibles se repartissent donc a nouveau, comme apres
  // un rendu -- c'est la meme operation, elle vit deja dans layoutColumns.
  const masonry = document.querySelector('.masonry');
  if (masonry) layoutColumns(masonry);
}
export function toggleGroup(id){
  if(hiddenThemes.has(id)) hiddenThemes.delete(id); else hiddenThemes.add(id);
  try{ localStorage.setItem('vigie.hiddenThemes', JSON.stringify([...hiddenThemes])); }catch(e){}
  document.querySelectorAll('.fchip[data-theme="'+id+'"]').forEach(b=>b.classList.toggle('active', !hiddenThemes.has(id)));
  applyFilter();
}

// Rendu d'UNE carte (reutilise par le rendu complet ET le rafraichissement par carte).
// D59 : une exception de rendu ne fait JAMAIS disparaitre la carte -- elle s'affiche
// en carte d'erreur minimale, diagnosticable, a sa place dans la grille.
export function cardHtmlSafe(m, groupLabel){
  try{ return cardHtml(m, groupLabel); }
  catch(e){
    console.error(L('ui.rendu-de-carte-en'), m && m.id, e);
    return '<div class="card st-error" data-module="'+esc((m&&m.id)||'?')+'" data-theme="'+esc((m&&m.theme)||'')+'">'
      +'<div class="card-head"><div class="card-titles"><span class="card-group">'+esc(groupLabel||'')+scopeHtml(m)+'</span>'
      +'<span class="name">'+esc((m&&m.label)||'Carte')+'</span></div>'
      +'<span class="badge error"><span class="ic vi">&#xE00C;</span>Affichage en erreur</span></div>'
      +'<div class="fields"><div class="frow"><span style="font-size:12.5px;color:var(--muted)">Le rendu de cette carte a échoué ('+esc(String(e&&e.message||e))+'). Les données du module sont intactes ; rechargez ou signalez.</span></div></div></div>';
  }
}
/* LA CADENCE D'UNE CARTE TENUE EN RETRAIT (contrat Module.pace).

   Pendant une partie, Vigie espace le recalcul des cartes qui ne regardent pas le jeu : jusqu'a vingt minutes,
   une heure pour les plus lourdes. Sans le dire, la carte donnerait une mesure d'il y a vingt minutes avec
   l'aplomb d'une mesure de l'instant. Seules les cartes reellement ralenties portent cette mention -- le serveur
   ne l'envoie pas pour les autres. */
export function paceLabel(seconds){
  const s = Number(seconds) || 0;
  if (s >= 3600) { const h = Math.round(s / 3600); return h > 1 ? `${h} h` : '1 h'; }
  if (s >= 60)   { return `${Math.round(s / 60)} min`; }
  return `${s} s`;
}
function paceHtml(m){
  if (!m || !m.pace || !m.pace.seconds) return '';
  const quoi = m.pace.reason === 'jeu' ? 'Une partie est en cours : Vigie se met en retrait pour la laisser tourner.'
                                       : 'Cette carte est recalculée moins souvent que d\'habitude.';
  return `<span class="card-pace" title="${esc(quoi)} Recalculée toutes les ${esc(paceLabel(m.pace.seconds))}.">en retrait · ${esc(paceLabel(m.pace.seconds))}</span>`;
}

/* LA FRAICHEUR D'UNE CARTE (contrat Module.freshness, S16).

   Une valeur vieille de vingt-deux heures s'affichait comme une valeur de la seconde. La carte porte desormais trois
   moments : quand la sonde a produit ce qu'elle montre, quand l'ordonnanceur est passe, et l'intervalle attendu.

   EN RETARD, ce n'est pas "une seconde de plus que l'intervalle" : un calcul de trente secondes qui arrive a
   trente-deux est a l'heure. On laisse passer le double de l'intervalle, et au moins deux minutes -- la meme regle
   que la mise en retrait, pour la meme raison : ne pas alerter sur du bruit.

   Un calcul qui ENCHAINE LES ECHECS est en retard quoi qu'il arrive : il ne reviendra pas tout seul. */
// DE QUI CETTE CARTE PARLE (D128). Rien pour l'ordinateur, qui est le cas ordinaire ; rien pour « mixed », dont ce
// sont les champs qui parlent. La mention ne sort que pour une carte qui ne dit QUE le compte connecte : sans elle,
// on lit la valeur d'un compte comme une valeur de l'ordinateur, ce qui est arrive le 05/10 avec winget.
function scopeHtml(m){
  if(!m || m.scope !== 'user') return '';
  return '<span class="card-scope" title="'+esc(L('ui.portee-compte-aide'))+'">'+esc(L('ui.portee-compte'))+'</span>';
}
export function cardAgeSeconds(iso){
  if (!iso) return null;
  const t = Date.parse(iso);
  if (isNaN(t)) return null;
  return Math.max(0, Math.round((Date.now() - t) / 1000));
}
function cardIsStale(m){
  const f = m && m.freshness;
  if (!f) return false;
  if (f.fails) return true;
  const age = cardAgeSeconds(f.computedAt);
  if (age === null) return false;
  const expected = Number(f.seconds) || 0;
  if (!expected) return false;
  return age > Math.max(120, 2 * expected);
}

function cardHtml(m, groupLabel){
  const st=['ok','warn','error','neutral'].includes(m.status)?m.status:'neutral';
  const stTxt={ok:'Conforme',warn:L('ui.voir'),error:L('ui.probleme')}[st];
  const stIc={ok:'&#xE00A;',warn:'&#xE00B;',error:'&#xE00C;'}[st];
  const actById={}; (m.actions||[]).forEach(a=>{ actById[a.id]=a; });
  const fields=(m.fields||[]).map(f=>{
    const stt=f.status||'neutral';
    const key=m.id+'::'+f.key;
    const fa=f.fixAction?actById[f.fixAction]:null;
    const fkind = fa ? (fa.kind||'immediate') : (f.fixAction ? 'confirm' : 'manual');
    const fconfirm = fa ? !!fa.confirm : true;
    fieldsByKey[key]=Object.assign({},f,{moduleId:m.id,fixKind:fkind,fixConfirm:fconfirm});
    const help=(f.help||'').replace(/"/g,'&quot;');
    const isProblem=(stt==='warn'||stt==='error');
    // SEUL le guide s'affiche sous la ligne : ce sont les informations SUPPLEMENTAIRES
    // (liste, valeurs detaillees, mode d'emploi). La description de ce que montre le
    // champ (`help`) reste une INFOBULLE.
    const detTxt=(f.guide||'');
    const open=openDetails.has(key)?' open':'';
    // Un detail COURT se deplie dans la carte ; un detail LONG ouvre une fenetre. Deplie
    // dans la carte, il la fait exploser en hauteur et noie le reste du tableau de bord
    // -- constate sur la liste des interfaces reseau, plusieurs dizaines de lignes.
    const aTable  = !!(f.table && f.table.rows && f.table.rows.length);
    const aTree   = !!f.tree;
    const detLong = aTable || aTree || (!!detTxt && (detTxt.length > 400 || detTxt.split(String.fromCharCode(10)).length > 8));
    // UN CLIC DOIT TOUJOURS FAIRE QUELQUE CHOSE (signale par l'utilisateur : le (i) et le
    // libelle restaient inertes). Trois cas :
    //   - detail court   -> il se deplie sous la ligne ;
    //   - detail long, tableau, arbre -> fenetre dediee ;
    //   - AIDE SEULE (ni guide ni tableau) -> fenetre aussi, au lieu d'un dépliant vide.
    // Avant, ce dernier cas appelait un depliant qui n'existait pas : rien ne se passait.
    const aQuoiVoir  = !!(detTxt || aTable || aTree || f.help);
    const clicDetail = !aQuoiVoir ? ''
      : ((detLong || !detTxt) ? `panel.ouvrirDetail('${key}')` : 'panel.toggleDetail(this)');
    const info=aQuoiVoir?`<button class="fhelp ${stt}" title="${help}" onclick="${clicDetail}"><span class="vi vi-fw vi-lg">&#xE007;</span></button>`:'';
    // BOUTON DE RESOLUTION (D66) : un champ orange ou rouge qui cite une action porte
    // TOUJOURS son bouton, juste sous la ligne. Il etait neutralise en dur ici (`const
    // solve=''`) : aucune carte n'en affichait, quelle que soit la sonde -- c'est le
    // defaut signale sur « Compteurs GPU ».
    // Le libelle vient de l'action quand la carte la declare aussi ; sinon le serveur
    // l'a completee depuis la declaration du fichier d'action.
    const interditeF = fa && (fa.allowed===false);
    // SON OPERATION TOURNE : il tourne aussi. La rangee d'actions savait deja le faire ;
    // le bouton de resolution, lui, restait intact et cliquable pendant que l'operation
    // qu'il venait de lancer se deroulait -- « il ne tourne pas, n'est pas grise, et est
    // toujours present » (constate le 28/08). Meme regle, meme rendu.
    // STRICTEMENT l'action qui tourne. Avec « ou busyAction inconnu », TOUS les boutons
    // de resolution de la carte se mettaient a tourner alors qu'un seul travaillait
    // (signale le 28/08). Quand le serveur ne dit pas quelle action tourne, aucun ne
    // tourne : le verrou les desactivera, ce qui est l'information juste.
    const solveRunning = !!m.busy && !!m.busyAction && m.busyAction===f.fixAction;
    const solve = (f.fixAction && isProblem)
      ? `<button class="fsolve sev-${fa?(fa.severity||'fix'):'fix'}${interditeF?' denied':''}${solveRunning?' busy':''}"${(interditeF||solveRunning)?' disabled':''}`
        // MEME SOURCE que le bouton du bas de carte : c'est la meme action, elle ne peut
        // pas se declarer de deux facons. Seule l'apparence differe.
        + attributsAction(fa || { id: f.fixAction }, m.id, fkind)
        + ` title="${att(interditeF?(fa.deniedReason||L('ui.action-reservee-un-compte')):((fa&&fa.help)||L('ui.resoudre-ce-point')))}">`
        + (solveRunning
             ? `<span class="spin"></span><span>${esc((fa&&fa.label)||L('ui.resoudre'))}…</span></button>`
             : `${ICONS[fkind]||''}<span>${esc((fa&&fa.label)||L('ui.resoudre'))}</span></button>`)
      : '';
    const det = (detTxt && !detLong) ? `<div class="field-detail ${stt}${open}" data-k="${key}">${esc(detTxt)}</div>` : '';
    return `<div class="frow">
      <div class="field"><span class="k"><span class="fdot ${stt}"></span><span class="fk-label${aQuoiVoir?' clickable':''}"${help?` title="${help}"`:''}${clicDetail?` onclick="${clicDetail}"`:''}>${f.label}</span>${info}</span><span class="v v-${stt}">${fmt(f)}</span></div>
      ${det}
      ${progressHtml(f)}
      ${solve?`<div class="frow-actions">${solve}</div>`:''}
    </div>`;
  }).join('');
  const busy=!!m.busy;
  // Aucune action n'est retiree de la barre : celle qui resout un champ y reste, meme
  // si le champ la designe. C'est en bas qu'on cherche les boutons.
  const actions=(m.actions||[]).map(a=>{
    const h=(a.help||'').replace(/"/g,'&quot;');
    const kind=a.kind||'immediate';
    const sev=a.severity||'neutral';
    // SEULE l'action reellement en cours s'anime. Toutes les autres restent lisibles, mais
    // desactivees : lancer une seconde operation pendant la premiere n'aurait pas de sens.
    // Animer les trois boutons faisait perdre lequel travaillait.
    // STRICTEMENT celle-la : sans busyAction, plus AUCUNE ne s'anime. Le repli
    // « ou busyAction inconnu » les faisait toutes tourner -- ce que ce commentaire
    // dit vouloir eviter, et que le code faisait quand meme.
    const cetteAction = busy && !!m.busyAction && m.busyAction===a.id;
    // Droits (D65) : une action que ce compte Windows n'a pas le droit de lancer reste
    // VISIBLE et dit pourquoi -- rien ne disparait d'une carte (D59). `allowed` n'est
    // absent que d'un etat servi par une version anterieure : on le lit alors comme oui.
    const interdite = (a.allowed===false);
    const bcls = cetteAction ? ' busy' : (interdite ? ' denied' : '');
    const dis = (busy || interdite) ? ' disabled' : '';
    const inner = cetteAction
      ? `<span class="spin"></span><span>${esc(a.busyLabel || (a.label+'…'))}</span>`
      : `${ICONS[kind]||''}<span>${esc(a.label)}</span>`;
    const bulle = interdite ? (a.deniedReason||L('ui.action-reservee-un-compte'))
                : (busy&&!cetteAction ? L('ui.operation-en-cours-sur') : (h||a.label));
    return `<button class="act k-${kind} sev-${sev}${bcls}"${dis}${attributsAction(a, m.id, kind)} title="${att(bulle)}">${inner}</button>`;
  }).join('');
  // A RECALCULER : la carte existe, sa mesure n'est pas encore faite. Elle s'affiche
  // avec sa place et son titre, en attente -- une carte qui disparait laisse un trou que
  // personne ne comprend, alors qu'une carte vide se lit tout de suite. Et si elle n'a
  // AUCUNE ligne a montrer, elle le dit : une carte vide et muette n'apprend rien.
  /*
      A CARD HELD BY AN OPERATION SHOWS NOTHING BUT THAT OPERATION (D102, D130).

      On 17/10, during a real Windows Update installation, the card announced the operation under its header AND
      showed its fields just below -- one of them stating that the count was unavailable, which is a statement
      about a measurement, while nothing could be measured as long as the lock was working. Two sentences
      contradicting each other on the same card. While an operation holds it, its fields and its buttons are not
      rendered; the note under the header says what is running and since when.

      Held means either: what the server rendered (`busy`), or what the page knows is running right now
      (`opsByCard`) -- the second arrives first, the first survives a reload.
  */
  const held = !!m.busy || !!(typeof opsByCard !== 'undefined' && opsByCard[m.id]);
  return `<div class="card st-${st}${m.busy?' busy':''}${m.pending?' card-loading':''}${m.mode?(' mode-'+m.mode):''}" data-module="${m.id}" data-theme="${m.theme}">
    <div class="card-head">
      <div class="card-titles"><span class="card-group">${esc(groupLabel||'')}${scopeHtml(m)}</span><span class="name">${m.label}</span>${paceHtml(m)}</div>
      ${stTxt?`<span class="badge ${st}"><span class="ic vi vi-fw">${stIc}</span>${stTxt}</span>`:''}
      <button class="card-refresh${cardIsStale(m)?' stale':''}" title="${L('ui.rafraichir-cette-carte')}${(m.ms!==undefined&&m.ms!==null)?` — ${L('ui.servie-en')}${m.ms} ms`:''}" onclick="panel.refreshCard('${m.id}',this,true)"><span class="cr-ic vi vi-fw vi-lg">&#xE008;</span></button>
      <button class="card-refresh card-menu" title="${L('ui.menu-de-cette-carte')}" onclick="panel.openCardMenu(event,'${m.id}','${m.theme}')"><span class="vi vi-fw vi-lg">&#xE009;</span></button>
    </div>
    <div class="fields">${held
      ? `<div class="frow"><span class="card-attente">${L('ui.carte-occupee')}</span></div>`
      : (fields || `<div class="frow"><span class="card-attente">${L(m.pending?'ui.carte-en-attente':'ui.carte-sans-ligne')}</span></div>`)}</div>
    ${(!held && actions)?`<div class="actions">${actions}</div>`:''}
  </div>`;
}

/*
    LE MENU DE LA CARTE -- un bouton a trois points annonce un MENU, pas une destination.

    Il ouvrait directement les parametres du module. C'etait la demande, elle n'avait pas
    ete respectee : les trois points doivent donner le CHOIX, dont l'acces aux parametres
    du module fait partie.
*/
function closeCardMenu(ev){
  // LE BOUTON QUI A OUVERT LE MENU N'EST PAS « AILLEURS ».
  //
  // Ce gestionnaire ecoute en phase de CAPTURE : il passait donc avant le clic du bouton.
  // Recliquer sur « ... » fermait puis rouvrait aussitot -- le menu ne se refermait
  // jamais par la ou on l'avait ouvert. On laisse le bouton decider dans ce cas.
  if (ev && ev.target && ev.target.closest && ev.target.closest('.card-menu')) return;
  const m = document.getElementById('cardMenu');
  if (m) m.remove();
  document.removeEventListener('click', closeCardMenu, true);
}
export function openCardMenu(ev, moduleId, theme){
  ev.stopPropagation();
  const already = document.getElementById('cardMenu');
  closeCardMenu();
  if (already && already.dataset.module === moduleId) return;   // second clic : on referme
  const el = document.createElement('div');
  el.id = 'cardMenu';
  el.className = 'card-menu-pop';
  el.dataset.module = moduleId;
  el.innerHTML =
      `<button type="button" data-do="settings">${L('ui.menu-parametres-du-module')}</button>`
    + `<button type="button" data-do="refresh">${L('ui.menu-recalculer-la-carte')}</button>`
    + `<button type="button" data-do="freshness">${L('ui.menu-detail-du-rafraichissement')}</button>`;
  document.body.appendChild(el);
  const r = ev.currentTarget.getBoundingClientRect();
  el.style.top  = (window.scrollY + r.bottom + 4) + 'px';
  el.style.left = (window.scrollX + Math.min(r.left, window.innerWidth - el.offsetWidth - 12)) + 'px';
  el.querySelector('[data-do="settings"]').onclick = () => { closeCardMenu(); openSettings('modules', theme); };
  el.querySelector('[data-do="refresh"]').onclick  = () => { closeCardMenu(); refreshCard(moduleId, null, true); };
  el.querySelector('[data-do="freshness"]').onclick = () => { closeCardMenu(); openFreshness(moduleId); };
  // Un clic AILLEURS referme : un menu qui reste ouvert derriere soi est un piege.
  setTimeout(() => document.addEventListener('click', closeCardMenu, true), 0);
}

/*
    UNE CARTE SANS MESURE SE DEMANDE, TOUT DE SUITE.

    Une carte « pas encore mesuree » ne se remplit pas toute seule : le serveur ne
    recalcule rien de lui-meme, et c'est voulu. Mais la page, elle, SAIT qu'il lui manque
    quelque chose -- et rester devant une carte vide en attendant un clic n'est pas un
    comportement, c'est un oubli.

    Elle demande donc chaque carte manquante, UNE PAR UNE : chacune a son propre appel,
    donc une carte lente ne retient pas les autres, et le chargement de la page n'a rien
    paye. C'est la seule demande automatique de recalcul, et elle ne porte que sur ce qui
    n'existe pas encore -- jamais sur ce qui est simplement vieux.
*/
let pendingAsked = new Set();
function askMissingCards(s){
  if(!API_MODE) return;
  const missing = (s && s.modules || []).filter(m => m && m.pending && m.id);
  for(const m of missing){
    if(pendingAsked.has(m.id)) continue;   // une seule fois par carte et par page
    pendingAsked.add(m.id);
    refreshCard(m.id, null, true).finally(() => pendingAsked.delete(m.id));
  }
}

export function wireCardActions(root){
  // Les boutons de la barre ET ceux des lignes (resolution d'un champ, D66) : meme
  // chemin d'execution, pour que l'etat « en cours » et les confirmations se comportent
  // pareil des deux endroits.
  (root||document).querySelectorAll('.actions button, .frow-actions button.fsolve').forEach(b=>{
    if (b.disabled) return;
    b.onclick=()=>doAction(b.dataset.a,b.dataset.m,b.dataset.c==='1',b.textContent,b.dataset.h,b,null,b.dataset.k,b.dataset.c2==='1',
                           { impact:b.dataset.imp, usage:b.dataset.usg, reversible:b.dataset.rev,
                             // Deux objets, donc du JSON : un attribut ne porte que du texte.
                             transition:(function(){ try{ return JSON.parse(b.dataset.trn||'null'); }catch(e){ return null; } })(),
                             steps:(function(){ try{ return JSON.parse(b.dataset.stp||'[]'); }catch(e){ return []; } })() });
  });
}

export function renderState(s, mode){
  // ON NE REMONTE PAS LA PAGE SOUS LES YEUX DE QUI LIT.
  //
  // Cette fonction reconstruit tout le tableau, et le navigateur remet alors le defilement a zero. La page relit le
  // cache toutes les minutes : quiconque lisait une carte en bas se retrouvait en haut, sans avoir rien demande.
  // Signale par le proprietaire le 30/09 -- « on doit pouvoir lire l'app sans etre gene ».
  //
  // On repose donc le defilement ou il etait, tout de suite apres avoir ecrit le DOM, dans le meme tour de boucle :
  // rien ne s'affiche entre les deux, donc rien ne saute a l'ecran.
  const scrollBefore = window.scrollY;
  const app=document.getElementById('app'); app.innerHTML='';
  fieldsByKey={};
  themeLabels={}; (s.themes||[]).forEach(t=>{ themeLabels[t.id]=t.label; });
  // AUCUN ETAT NE FAIT DISPARAITRE UNE CARTE (D59). Une sonde en cours de recalcul n'a
  // rien dans le cache du serveur : son module manque alors dans /state. On garde donc la
  // DERNIERE version connue de la carte, marquee « recalcul en cours », au lieu de la
  // retirer -- signale par l'utilisateur : la carte Windows Update disparaissait pendant
  // presque une minute apres un clic.
  const recus = new Set((s.modules||[]).map(m=>m.id));
  const survivants = (lastModules||[]).filter(m=>m && !recus.has(m.id))
    .map(m=>Object.assign({}, m, { busy:true, _survivant:true }));
  if(survivants.length){ s = Object.assign({}, s, { modules: (s.modules||[]).concat(survivants) }); }
  lastModules=(s.modules||[]).map(m=>{ const c=Object.assign({},m); delete c._survivant; return c; });
  // LE TROISIEME MOMENT (S16) : les deux autres viennent du serveur, celui-ci n'existe que dans la page.
  lastStateReadAt = new Date().toISOString();
  lastUnits=(s.units||[]).slice();
  lastHost=s.host||'';
  let worst='ok';
  let html='';
  (s.themes||[]).forEach(theme=>{
    (s.modules||[]).filter(m=>m.theme===theme.id).forEach(m=>{
      if(STATUS_RANK[m.status]>STATUS_RANK[worst]) worst=m.status;
      html+=cardHtmlSafe(m, theme.label);
    });
  });
  (s.modules||[]).filter(m=>!themeLabels[m.theme]).forEach(m=>{
    if(STATUS_RANK[m.status]>STATUS_RANK[worst]) worst=m.status;
    html+=cardHtmlSafe(m, m.theme||'');
  });
  // Filtre rapide par groupe (afficher/masquer)
  const themesWithMods=(s.themes||[]).filter(t=>(s.modules||[]).some(m=>m.theme===t.id));
  if(themesWithMods.length>1){
    const fbar=document.createElement('div'); fbar.className='filterbar';
    fbar.innerHTML='<span class="flabel">Groupes</span>'+themesWithMods.map(t=>{
      const active=!hiddenThemes.has(t.id);
      return `<button class="fchip${active?' active':''}" data-theme="${t.id}" onclick="panel.toggleGroup('${t.id}')" title="${active?'Masquer':'Afficher'} ${L('ui.le-groupe')} ${esc(t.label)} »">${esc(t.label)}</button>`;
    }).join('');
    app.appendChild(fbar);
  }
  const masonry=document.createElement('div'); masonry.className='masonry';
  masonry.innerHTML=html;
  layoutColumns(masonry);
  app.appendChild(masonry);
  wireCardActions(masonry);
  // Le defilement, remis ou il etait (voir en tete de cette fonction). Apres layoutColumns, donc sur une page qui a
  // deja sa hauteur definitive : repose avant, il aurait ete borne a la hauteur d'un tableau encore vide.
  if (scrollBefore) { window.scrollTo(0, scrollBefore); }
  applyOperationLock();
  // Si le rangement est en cours, les cartes fraichement rendues redeviennent
  // saisissables : le mode et l'affichage restent d'accord.
  if(modeReorg) armerGlisser();
  applyFilter();
  askMissingCards(s);
  const g=document.getElementById('global'), gt=document.getElementById('globalTxt');
  // Le badge de l'en-tete et le liseré disent la MEME chose : l'etat de l'application
  // elle-meme (connectee, en maquette, en erreur). Ils portaient auparavant deux
  // informations differentes -- badge rouge « Action requise » au-dessus d'un liseré vert
  // -- et se contredisaient a l'oeil. La sante des cartes se lit sur les cartes.
  const uiState = mode==='live'
    ? { col:'var(--ok)',   txt:L('ui.connecte'),  aide:L('ui.connecte-api-locale-les') }
    : { col:'var(--warn)', txt:'Maquette',  aide:L('ui.le-service-est-pas') };
  g.querySelector('.dot').style.cssText=`width:9px;height:9px;border-radius:50%;background:${uiState.col}`;
  gt.textContent=uiState.txt;
  gt.style.color=uiState.col;
  g.title=uiState.aide;
  const meta=document.getElementById('lastRefresh');
  meta.textContent=L('ui.mis-jour')+new Date().toLocaleTimeString('fr-FR');
  // CE QUI A PRIS DU TEMPS, dans l'infobulle : le total, puis chaque phase du serveur et
  // les trois cartes les plus lentes. Un chiffre unique ne dit pas ou regarder.
  try{
    const ph = s.timings || {};
    const rows = Object.keys(ph).map(k=>`${k} : ${ph[k]} ms`);
    const total = Object.keys(ph).reduce((a,k)=>a+(+ph[k]||0),0);
    const slowest = (s.modules||[]).filter(m=>m.ms!==undefined&&m.ms!==null)
                    .sort((a,b)=>b.ms-a.ms).slice(0,3).map(m=>`${m.label} : ${m.ms} ms`);
    if(rows.length){
      meta.textContent += ` · ${Math.round(total)} ms`;
      // LES SAUTS DE LIGNE SONT CONSTRUITS, PAS ECHAPPES. Ecrits « backslash-n » depuis
      // un script, ils sont devenus de VRAIS retours a la ligne dans une chaine JS : la
      // page ne se chargeait plus du tout, bloquee sur son ecran d'attente (01/09).
      const saut = String.fromCharCode(10);
      meta.title = L('ui.temps-de-reponse') + saut + rows.join(saut)
                 + (slowest.length ? (saut + saut + L('ui.cartes-les-plus-lentes') + saut + slowest.join(saut)) : '');
    }
  }catch(e){}
  setMachineName(s.host);
  const mb=document.getElementById('modebar'); const isBusy=mb.classList.contains('busy'); mb.className='modebar '+(mode==='live'?'ok':'warn')+(isBusy?' busy':''); mb.title=(mode==='live'?L('ui.connecte-api-locale-donnees'):L('ui.maquette-back-non-lance')); mb.textContent='';
}

// Repartit les cartes en COLONNES REELLES, une fois, dans un ordre stable.
//
// La largeur d'une colonne (280 px + gouttiere) reprend celle de l'ancienne mise en
// page : le nombre de colonnes ne change donc qu'au redimensionnement de la fenetre.
//
// L'equilibrage se fait sur une hauteur ESTIMEE (nombre de lignes et de boutons), et
// surtout PAS sur la hauteur mesuree : une carte qui passe en « operation en cours »
// grandit, et rebalancer a ce moment-la ferait exactement le saut qu'on veut supprimer.
// L'estimation, elle, ne depend que de ce que la carte CONTIENT.
export const COL_WIDTH = 296;
