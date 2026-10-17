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
// Persisted: a reload (frequent -- the app reloads on every build) must not bring back
// the groups the user has hidden.
export let hiddenThemes=new Set();
try{ hiddenThemes=new Set(JSON.parse(localStorage.getItem('vigie.hiddenThemes')||'[]')); }catch(e){}
function applyFilter(){
  document.querySelectorAll('.masonry .card[data-theme]').forEach(c=>{
    c.style.display = hiddenThemes.has(c.dataset.theme) ? 'none' : '';
  });
  // AND WE REDISTRIBUTE. Hiding a card takes it out of the display, not out of its
  // column: unticking a group left empty columns and a hole in the middle of the grid
  // (seen on 01/09). So the visible cards are shared out again, as after a rendering --
  // it is the same operation, and it already lives in layoutColumns.
  const masonry = document.querySelector('.masonry');
  if (masonry) layoutColumns(masonry);
}
export function toggleGroup(id){
  if(hiddenThemes.has(id)) hiddenThemes.delete(id); else hiddenThemes.add(id);
  try{ localStorage.setItem('vigie.hiddenThemes', JSON.stringify([...hiddenThemes])); }catch(e){}
  document.querySelectorAll('.fchip[data-theme="'+id+'"]').forEach(b=>b.classList.toggle('active', !hiddenThemes.has(id)));
  applyFilter();
}

// Rendering of ONE card (reused by the full rendering AND by the per-card refresh).
// D59: a rendering exception NEVER makes the card disappear -- it is shown as a minimal
// error card, diagnosable, in its place in the grid.
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
/* THE PACE OF A CARD HELD BACK (Module.pace contract).

   During a game, Vigie spaces out the recomputing of the cards that are not watching the game: up to twenty
   minutes, an hour for the heaviest. Without saying so, the card would give a measure from twenty minutes ago
   with the assurance of a measure from this instant. Only the cards really slowed down carry this mention --
   the server does not send it for the others. */
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

/* HOW FRESH A CARD IS (Module.freshness contract, S16).

   A value twenty-two hours old was displayed like a value from this second. The card now carries three moments:
   when the probe produced what it shows, when the scheduler came by, and the interval expected.

   LATE is not "one second more than the interval": a thirty-second computation arriving at thirty-two is on
   time. We allow twice the interval, and at least two minutes -- the same rule as holding back, for the same
   reason: not to raise an alarm about noise.

   A computation that FAILS AGAIN AND AGAIN is late whatever happens: it will not come back on its own. */
// WHO THIS CARD SPEAKS OF (D128). Nothing for the computer, which is the ordinary case; nothing for "mixed", whose
// fields speak for themselves. The mention only comes out for a card that says ONLY the connected account: without
// it, one reads an account's value as the computer's, which happened on 05/10 with winget.
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
    // ONLY the guide is shown under the row: those are the EXTRA pieces of information
    // (a list, detailed values, instructions). The description of what the field shows
    // (`help`) stays a TOOLTIP.
    const detTxt=(f.guide||'');
    const open=openDetails.has(key)?' open':'';
    // A SHORT detail unfolds inside the card; a LONG detail opens a window. Unfolded in
    // the card, it blows its height up and drowns the rest of the dashboard -- seen on
    // the list of network interfaces, several dozen rows.
    const aTable  = !!(f.table && f.table.rows && f.table.rows.length);
    const aTree   = !!f.tree;
    const detLong = aTable || aTree || (!!detTxt && (detTxt.length > 400 || detTxt.split(String.fromCharCode(10)).length > 8));
    // A CLICK MUST ALWAYS DO SOMETHING (reported by the user: the (i) and the label
    // stayed inert). Three cases:
    //   - a short detail -> it unfolds under the row;
    //   - a long detail, a table, a tree -> a dedicated window;
    //   - HELP ALONE (no guide, no table) -> a window too, instead of an empty fold.
    // Before, that last case called a fold that did not exist: nothing happened.
    const aQuoiVoir  = !!(detTxt || aTable || aTree || f.help);
    const clicDetail = !aQuoiVoir ? ''
      : ((detLong || !detTxt) ? `panel.ouvrirDetail('${key}')` : 'panel.toggleDetail(this)');
    const info=aQuoiVoir?`<button class="fhelp ${stt}" title="${help}" onclick="${clicDetail}"><span class="vi vi-fw vi-lg">&#xE007;</span></button>`:'';
    // THE FIX BUTTON (D66): an amber or red field that names an action ALWAYS carries its
    // button, right under the row. It was switched off in hard here (`const solve=''`):
    // not one card showed one, whatever the probe -- that is the fault reported about
    // "GPU counters".
    // The label comes from the action when the card declares it too; otherwise the server
    // completed it from the action file's own declaration.
    const interditeF = fa && (fa.allowed===false);
    // ITS OPERATION IS RUNNING: it spins too. The row of actions already knew how to do
    // that; the fix button stayed intact and clickable while the operation it had just
    // started was running -- "it does not spin, it is not greyed out, and it is still
    // there" (seen on 28/08). Same rule, same rendering.
    // STRICTLY the action that is running. With "or busyAction unknown", EVERY fix button
    // of the card started spinning while only one was working (reported on 28/08). When
    // the server does not say which action is running, none spins: the lock will switch
    // them off, which is the right information.
    const solveRunning = !!m.busy && !!m.busyAction && m.busyAction===f.fixAction;
    const solve = (f.fixAction && isProblem)
      ? `<button class="fsolve sev-${fa?(fa.severity||'fix'):'fix'}${interditeF?' denied':''}${solveRunning?' busy':''}"${(interditeF||solveRunning)?' disabled':''}`
        // THE SAME SOURCE as the button at the bottom of the card: it is the same action,
        // it cannot declare itself two ways. Only the appearance differs.
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
  // No action is taken out of the bar: the one that fixes a field stays there, even if
  // the field names it. The buttons are looked for at the bottom.
  const actions=(m.actions||[]).map(a=>{
    const h=(a.help||'').replace(/"/g,'&quot;');
    const kind=a.kind||'immediate';
    const sev=a.severity||'neutral';
    // ONLY the action really under way is animated. All the others stay readable, but
    // switched off: starting a second operation during the first would make no sense.
    // Animating all three buttons made one lose which was working.
    // STRICTLY that one: without busyAction, NONE is animated any more. The fallback
    // "or busyAction unknown" made them all spin -- which this very comment says it wants
    // to avoid, and which the code did anyway.
    const cetteAction = busy && !!m.busyAction && m.busyAction===a.id;
    // Rights (D65): an action this Windows account is not allowed to start stays VISIBLE
    // and says why -- nothing disappears from a card (D59). `allowed` is only missing
    // from a state served by an earlier version: we then read it as yes.
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
  // TO BE RECOMPUTED: the card exists, its measure is not done yet. It is shown with its
  // place and its title, waiting -- a card that disappears leaves a hole nobody
  // understands, while an empty card reads at once. And if it has NO row to show, it says
  // so: a card both empty and silent teaches nothing.
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
  // THE BUTTON THAT OPENED THE MENU IS NOT "SOMEWHERE ELSE".
  //
  // This handler listens in the CAPTURE phase: it therefore ran before the button's own
  // click. Clicking "..." again closed it and reopened it straight away -- the menu never
  // closed by the very place it had been opened from. We let the button decide in that case.
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
  // A click ELSEWHERE closes it: a menu left open behind one is a trap.
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
  // The bar's buttons AND the rows' ones (fixing a field, D66): the same execution path,
  // so that the "under way" state and the confirmations behave the same in both places.
  //
  (root||document).querySelectorAll('.actions button, .frow-actions button.fsolve').forEach(b=>{
    if (b.disabled) return;
    b.onclick=()=>doAction(b.dataset.a,b.dataset.m,b.dataset.c==='1',b.textContent,b.dataset.h,b,null,b.dataset.k,b.dataset.c2==='1',
                           { impact:b.dataset.imp, usage:b.dataset.usg, reversible:b.dataset.rev,
                             // Two objects, so JSON: an attribute carries nothing but text.
                             transition:(function(){ try{ return JSON.parse(b.dataset.trn||'null'); }catch(e){ return null; } })(),
                             steps:(function(){ try{ return JSON.parse(b.dataset.stp||'[]'); }catch(e){ return []; } })() });
  });
}

export function renderState(s, mode){
  // WE DO NOT PULL THE PAGE BACK UP UNDER THE EYES OF WHOEVER IS READING.
  //
  // This function rebuilds the whole board, and the browser then sets the scrolling back to zero. The page re-reads
  // the cache every minute: anyone reading a card at the bottom found themselves at the top, having asked for
  // nothing. Reported by the owner on 30/09 -- "one must be able to read the app without being bothered".
  //
  // So the scrolling is put back where it was, immediately after writing the DOM, in the same turn of the loop:
  // nothing is displayed between the two, so nothing jumps on screen.
  const scrollBefore = window.scrollY;
  const app=document.getElementById('app'); app.innerHTML='';
  fieldsByKey={};
  themeLabels={}; (s.themes||[]).forEach(t=>{ themeLabels[t.id]=t.label; });
  // NO STATE MAKES A CARD DISAPPEAR (D59). A probe being recomputed has nothing in the
  // server's cache: its module is then missing from /state. So we keep the LAST known
  // version of the card, marked "being recomputed", instead of removing it -- reported by
  // the user: the Windows Update card disappeared for almost a minute after
  // a click.
  const recus = new Set((s.modules||[]).map(m=>m.id));
  const survivants = (lastModules||[]).filter(m=>m && !recus.has(m.id))
    .map(m=>Object.assign({}, m, { busy:true, _survivant:true }));
  if(survivants.length){ s = Object.assign({}, s, { modules: (s.modules||[]).concat(survivants) }); }
  lastModules=(s.modules||[]).map(m=>{ const c=Object.assign({},m); delete c._survivant; return c; });
  // THE THIRD MOMENT (S16): the other two come from the server, this one exists only in the page.
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
  // Quick filter by group (show/hide)
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
  // The scrolling, put back where it was (see the head of this function). After layoutColumns, so on a page that
  // already has its final height: put back before, it would have been capped to the height of an empty board.
  if (scrollBefore) { window.scrollTo(0, scrollBefore); }
  applyOperationLock();
  // If the rearranging is under way, the freshly rendered cards become grabbable again:
  // the mode and the display stay in agreement.
  if(modeReorg) armerGlisser();
  applyFilter();
  askMissingCards(s);
  const g=document.getElementById('global'), gt=document.getElementById('globalTxt');
  // The header's badge and the stripe say the SAME thing: the state of the application
  // itself (connected, on mock data, in error). They used to carry two different pieces
  // of information -- a red "Action required" badge above a green stripe -- and
  // contradicted each other to the eye. The cards' health is read on the cards.
  const uiState = mode==='live'
    ? { col:'var(--ok)',   txt:L('ui.connecte'),  aide:L('ui.connecte-api-locale-les') }
    : { col:'var(--warn)', txt:'Maquette',  aide:L('ui.le-service-est-pas') };
  g.querySelector('.dot').style.cssText=`width:9px;height:9px;border-radius:50%;background:${uiState.col}`;
  gt.textContent=uiState.txt;
  gt.style.color=uiState.col;
  g.title=uiState.aide;
  const meta=document.getElementById('lastRefresh');
  meta.textContent=L('ui.mis-jour')+new Date().toLocaleTimeString('fr-FR');
  // WHAT TOOK TIME, in the tooltip: the total, then each of the server's phases and the
  // three slowest cards. A single figure does not say where to look.
  try{
    const ph = s.timings || {};
    const rows = Object.keys(ph).map(k=>`${k} : ${ph[k]} ms`);
    const total = Object.keys(ph).reduce((a,k)=>a+(+ph[k]||0),0);
    const slowest = (s.modules||[]).filter(m=>m.ms!==undefined&&m.ms!==null)
                    .sort((a,b)=>b.ms-a.ms).slice(0,3).map(m=>`${m.label} : ${m.ms} ms`);
    if(rows.length){
      meta.textContent += ` · ${Math.round(total)} ms`;
      // LINE BREAKS ARE BUILT, NOT ESCAPED. Written as "backslash n" from a script, they
      // became REAL line breaks inside a JS string: the page no longer loaded at all,
      // stuck on its waiting screen (01/09).
      const saut = String.fromCharCode(10);
      meta.title = L('ui.temps-de-reponse') + saut + rows.join(saut)
                 + (slowest.length ? (saut + saut + L('ui.cartes-les-plus-lentes') + saut + slowest.join(saut)) : '');
    }
  }catch(e){}
  setMachineName(s.host);
  const mb=document.getElementById('modebar'); const isBusy=mb.classList.contains('busy'); mb.className='modebar '+(mode==='live'?'ok':'warn')+(isBusy?' busy':''); mb.title=(mode==='live'?L('ui.connecte-api-locale-donnees'):L('ui.maquette-back-non-lance')); mb.textContent='';
}

// Shares the cards out into REAL COLUMNS, once, in a stable order.
//
// A column's width (280 px plus the gutter) takes over from the former layout: the number
// of columns therefore only changes when the window is resized.
//
// Balancing works on an ESTIMATED height (the number of rows and buttons), and certainly
// NOT on the measured height: a card going to "operation under way" grows, and rebalancing
// at that moment would make exactly the jump we want to remove. The estimate depends only
// on what the card CONTAINS.
export const COL_WIDTH = 296;
