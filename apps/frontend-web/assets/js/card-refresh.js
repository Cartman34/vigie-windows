// @author Florent HAZARD <f.hazard@sowapps.com>
import { API, API_MODE, TOKEN } from './api.js';
import { cardHtmlSafe, hiddenThemes, lastModules, themeLabels, wireCardActions } from './cards.js';
import { updateNotif } from './notifications.js';
import { applyOperationLock } from './operation-lock.js';
import { markOnline } from './operations.js';

function replaceCardDom(m){
  const sel='.card[data-module="'+((window.CSS&&CSS.escape)?CSS.escape(m.id):m.id)+'"]';
  const card=document.querySelector(sel);
  if(!card) return null;
  const tmp=document.createElement('div');
  // The GROUP's label comes from the theme catalogue. If it is missing -- the card was
  // refreshed before the first /state -- we keep THE ONE ALREADY ON SCREEN rather than
  // falling back on the technical identifier: the Accounts card ended up titled
  // "ACCOUNTS" (seen on 27/08).
  const alreadyShown=(card.querySelector('.card-group')||{}).textContent;
  tmp.innerHTML=cardHtmlSafe(m, themeLabels[m.theme]||alreadyShown||m.theme||'');
  const fresh=tmp.firstElementChild;
  // THE GROUP HIDES THE REST. The new node arrives without the display:none the filter
  // had set on the old one: a card of an unticked group therefore came back on screen as
  // soon as it refreshed on its own -- and they refresh all the time now that the server
  // computes in the background (seen on 30/09 on the Accounts group).
  if(hiddenThemes.has(fresh.dataset.theme)) fresh.style.display='none';
  card.replaceWith(fresh);
  wireCardActions(fresh);
  // The server has the last word: if the card is no longer busy, the lock falls.
  applyOperationLock();
  const i=(lastModules||[]).findIndex(x=>x.id===m.id);
  if(i>=0) lastModules[i]=m; else lastModules.push(m);
  return fresh;
}
// Fetches a module's state (live) or the last one known (mock).
async function fetchModule(moduleId, frais){
  if(API_MODE){
    try{
      // fresh: the server RECOMPUTES the card and waits for the result. Reserved for the
      // card's own button; following a background task reads the cache instead.
      const r=await fetch(API+'/modules/'+encodeURIComponent(moduleId)+(frais?'?fresh=1':''),{ headers:{ Authorization:'Bearer '+TOKEN } });
      if(r.ok){ markOnline(); return await r.json(); }
    }catch(e){}
    return null;
  }
  return (lastModules||[]).find(x=>x.id===moduleId)||null;
}
// Refreshes ONE card (through GET /modules/:id), without reloading the whole page.
export async function refreshCard(moduleId, btn, frais){
  const sel='.card[data-module="'+((window.CSS&&CSS.escape)?CSS.escape(moduleId):moduleId)+'"]';
  const card=document.querySelector(sel);
  if(!card) return;
  card.classList.add('card-loading');
  const m=await fetchModule(moduleId, frais);
  if(m){ replaceCardDom(m); } else { card.classList.remove('card-loading'); }
}
// Polls a card until a background task ends (m.busy false), without blocking.
//
// A ONE-HOUR CEILING, not three minutes. A package update commonly takes ten minutes or
// more: the old ceiling gave up in the middle of the work, the card stayed "under way"
// and nothing more ever came -- seen on a Chocolatey update.
// The elapsed counter is shown: an asynchronous operation must be SEEN to be alive.
const POLL_MAX_MS = 3600000;
export async function pollCardUntilIdle(moduleId, entry, name){
  const startTs=Date.now();
  let delay=1400;
  const ecoule=()=>{ const s=Math.round((Date.now()-startTs)/1000);
                     return s<60 ? s+' s' : Math.floor(s/60)+' min '+(s%60)+' s'; };
  async function tick(){
    const m=await fetchModule(moduleId);
    if(m) replaceCardDom(m);
    // A MISSING answer is not an ending: the server may be recomputing (anti-stampede
    // lock) and return nothing for this card. The old test took that emptiness for a
    // success and announced "finished" straight away, while the background task was still
    // running and the value on screen still read "not checked".
    const stillBusy = (!m) || m.busy;
    if(stillBusy && (Date.now()-startTs)<POLL_MAX_MS){
      if(entry) updateNotif(entry,'running', name+' : en cours depuis '+ecoule()+'…');
      delay=Math.min(delay+400, 4000);
      setTimeout(tick, delay);
    } else if(stillBusy){
      // We hand the card back in a readable state instead of leaving it spinning for ever.
      refreshCard(moduleId);
      if(entry) updateNotif(entry,'error', name+L('ui.toujours-en-cours-apres')+ecoule()+L('ui.suivi-abandonne'));
    } else {
      // THE SAME CHAIN AT THE END OF A BACKGROUND TASK. The worker invalidates the card as it finishes, so this
      // last read of the cache still carries the previous rendering: we recompute the card, once, on
      // l'evenement « plus occupee ».
      refreshCard(moduleId, null, true);
      if(entry) updateNotif(entry,'done', name+L('ui.termine-en')+ecoule()+'.');
    }
  }
  setTimeout(tick, 900);
}
