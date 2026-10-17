// @author Florent HAZARD <f.hazard@sowapps.com>
import { REPO_URL, SPLASH_FADE_MS, SPLASH_MIN_MS } from './config.js';
import { runningOperation } from './operation-lock.js';
import { modeReorg } from './reorder.js';
import { unitsOpen } from './settings.js';

export function wireRepoLinks(){
  const label = REPO_URL.replace(/^https?:\/\//, '');
  document.querySelectorAll('[data-repo-link]').forEach(a=>{
    a.href = REPO_URL;
    a.target = '_blank';          // jamais dans la fenetre --app, qui n'a pas de barre d'adresse
    a.rel = 'noopener';
    if(a.dataset.repoLink === 'label') a.textContent = label;
    if(!a.title) a.title = L('ui.ouvrir-le-depot-du') + label + ')';
  });
}

// The machine's name appears in two places: the bar's title and the splash subtitle.
export function setMachineName(host){
  if(!host) return;
  const at = document.getElementById('appTitle');  if(at) at.textContent = host;
  const ss = document.getElementById('splashSub'); if(ss) ss.textContent = host;
  document.title = host + ' — Vigie';
}

export function setFootVersion(){
  const el = document.getElementById('footVersion'); if(!el) return;
  const v = window.APP_VERSION;
  // "version v0.1" would say it twice: the prefix already carries the meaning.
  el.textContent = (v && !v.includes('__')) ? v : 'maquette';
}

// Clears the loading screen, once only, after a minimum time on display.
// Called on error too: an error message has to become visible.
// REAL loading progress, in three known steps. As long as progress is unknown, the gauge
// climbs in a loop; as soon as a step is passed, it shows the true advance. The "known
// progress" mode existed in CSS with nothing to switch it on: decoration, until the three
// steps below started feeding it.
export function progresSplash(fraction){
  const el = document.getElementById('splash');
  if(!el || splashDone) return;
  el.classList.add('splash-determine');
  el.style.setProperty('--splash-frac', String(Math.max(0, Math.min(1, fraction))));
}
let splashDone = false;
const splashShownAt = Date.now();
export function hideSplash(){
  if(splashDone) return;
  splashDone = true;
  const el = document.getElementById('splash'); if(!el) return;
  const wait = Math.max(0, SPLASH_MIN_MS - (Date.now() - splashShownAt));
  setTimeout(()=>{
    el.classList.add('splash-off');
    setTimeout(()=>{ el.hidden = true; }, SPLASH_FADE_MS);
  }, wait);
}

// THE BUTTON FOLLOWS THE STATE OF THE MACHINE. Live when it would refuse, it lies; inert
// with its reason in a tooltip, it teaches.
export function updateRefreshButton(){
  const btn=document.getElementById('btnRefresh');
  if(!btn) return;
  const op = runningOperation();
  const pris = !!(op && (op.ressources || []).includes('machine'));
  if(btn.dataset.titleWas === undefined) btn.dataset.titleWas = btn.title;
  btn.classList.toggle('inerte', pris);
  btn.title = pris ? (L('ui.recalcul-pendant-operation') + (op.titre || '')) : btn.dataset.titleWas;
}
export function setLoading(on, complete){
  const btn=document.getElementById('btnRefresh');
  // An ICON-ONLY button: the label lives in the tooltip, as for the other icon buttons.
  // The spinning animation stays, it is what says that work is happening.
  if(btn){ btn.disabled=on; btn.innerHTML = on ? '<span class="spin"></span>' : '↻'; }
  // The application's stripe AND the header both say a refresh is happening: the first is
  // seen out of the corner of the eye, the second writes it down.
  const mb=document.getElementById('modebar');
  if(mb) mb.classList.toggle('busy', !!on);
  // ONLY FOR A REAL RECOMPUTE, never for the automatic re-reading.
  //
  // During a full recompute the cards' values are on borrowed time: dimming them says so, and their buttons stay
  // clickable. But the page RE-READS the cache every minute, and that re-reading went through the same path: the
  // whole interface dimmed every time. Reported by the owner on 30/09 -- "it greys out the interface, it is too
  // visible, it should not show because it happens very often".
  //
  // The header's stripe goes on saying that something is happening: discreet, it does not interrupt the reading.
  document.querySelectorAll('.card').forEach(c => c.classList.toggle('card-loading', !!(on && complete)));
  const meta=document.getElementById('lastRefresh');
  if(meta){
    meta.classList.toggle('busy', !!on);
    if(on){
      if(meta.dataset.textBefore === undefined) meta.dataset.textBefore = meta.textContent;
      // TWO GESTURES, TWO SENTENCES. "Refreshing" said the same thing for a re-reading of
      // the state -- a few tenths of a second, served from the cache -- and for a full
      // recompute, which redoes every measure and can last a minute. The wait does not
      // mean the same thing, so it must not carry the same words.
      meta.textContent = complete ? L('ui.recalcul-en-cours') : L('ui.actualisation-en-cours');
    } else {
      // If the rendering did not happen (a network error), the text would have stayed on "under way".
      if((meta.textContent === L('ui.actualisation-en-cours') || meta.textContent === L('ui.recalcul-en-cours'))
         && meta.dataset.textBefore !== undefined) {
        meta.textContent = meta.dataset.textBefore;
      }
      delete meta.dataset.textBefore;
    }
  }
  // Non-blocking: the existing cards are kept while the refresh happens.
  // Only on the very first load (no card at all) do we show a marker.
  const app=document.getElementById('app');
  if(on && app && !app.querySelector('.masonry')){
    app.innerHTML='<div class="loading-note"><span class="spin"></span> Chargement du panneau…</div>';
  }
}
// Is the page BUSY SERVING someone? We do not redraw under anybody's fingers: cards being
// rearranged, a dialog window open, the settings panel unfolded, or the notifications
// drawer open. The automatic refresh will wait for the next turn; an EXPLICIT request
// (the Refresh button) goes through.
export function pageBusy(){
  if(modeReorg) return 'rangement';
  const modale = document.getElementById('hdsBack');
  if(modale && modale.classList.contains('show')) return L('ui.fenetre-ouverte');
  if(typeof unitsOpen !== 'undefined' && unitsOpen) return L('ui.reglages-ouverts');
  const tiroir = document.getElementById('drawer');
  if(tiroir && tiroir.classList.contains('open')) return 'tiroir ouvert';
  return null;
}
