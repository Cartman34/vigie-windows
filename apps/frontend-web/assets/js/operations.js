// @author Florent HAZARD <f.hazard@sowapps.com>
import { API, API_MODE, TOKEN, openDetails } from './api.js';
import { refreshCard } from './card-refresh.js';
import { lastModules } from './cards.js';
import { addNotif, notifs, updateNotif } from './notifications.js';
import { applyOperationLock, clearCardBusy, opsByCard, paintOperationNotes, resetOpsByCard } from './operation-lock.js';

// ===== THE OPERATIONS ARE SHARED (D95) =======================================
//
// Notifications used to live in the PAGE: a second window knew nothing of an operation
// started from the first, and a page opened AFTER a deployment left saw no trace of it.
// The server knows -- it holds the operation markers and their results. So every page
// aligns on it, at short intervals.
//
// A notification carried by the server is recognised by its KEY (module plus action): the
// page that started the operation keeps its own, the others create an identical one, and
// nobody ends up with a duplicate.
export let opsConnues = {};      // cle -> id de notification locale
export const OPS_MS = 4000;

function operationKey(o){ return (o.module || '') + '|' + (o.action || ''); }

// THE STATE MAY COME FROM SOMEWHERE OTHER THAN THE POLL.
//
// An action's answer already carries it: using it at once avoids waiting for the next
// turn (up to 4 s) and removes the race that created a second notification for the same
// operation.
export async function syncOperations(etatFourni){
  if(!API_MODE) return;
  let uiState = etatFourni || null;
  if(!uiState){
    try{
      const r = await fetch(API + '/operations', { headers:{ Authorization:'Bearer ' + TOKEN } });
      if(!r.ok) return;
      uiState = await r.json();
      markOnline();   // le serveur a repondu : la page n'est plus hors ligne
    }catch(e){ return; }
  }

  // WHAT THE SERVER SAYS OF THE OPERATIONS UNDER WAY, kept as it is and arranged by card.
  //
  // The page used to rebuild it from the DOM, reading `busyResources` on the card -- which most cards do not
  // carry. The resources therefore arrived empty, and the fallback "we do not know what it holds, we block
  // everything" applied: on 06/10, a disk scan that holds only the disk also switched off the Chocolatey
  // button. The /operations route carries the label, the action, the resources and the start time.
  resetOpsByCard();
  for(const op of (uiState.running || [])){
    if(op && op.module) opsByCard[op.module] = op;
  }
  // WHAT IS BUSY IS READ ON THE LIVING, NEVER ON A RENDERING (D130). A card computed during an operation carries
  // `busy` in its rendering, and that rendering is served until the next recompute -- a day, for the packages
  // card. The card stayed grey after the end, and one had to reload the page. The list of operations says what
  // is running at this instant: it is the one that sets and removes the class.
  document.querySelectorAll('.card').forEach(card => {
    card.classList.toggle('busy', !!opsByCard[card.dataset.module]);
  });
  for(const m of (lastModules || [])){
    if(!opsByCard[m.id]){ m.busy = false; delete m.busyAction; delete m.busyResources; }
  }
  paintOperationNotes();
  applyOperationLock();
  const enCours = new Set();
  for(const op of (uiState.running || [])){
    const cle = operationKey(op);
    enCours.add(cle);
    // AN OPERATION HAS ONLY ONE NOTIFICATION, and the next one REPLACES the previous.
    //
    // We do not trust the key register alone: it may have been emptied -- page reloaded,
    // notification cleared by hand -- while a notification of that operation still exists.
    // So we also look by the key CARRIED BY the notification. Without that, two
    // announcements of the same thing end up side by side.
    const connue = opsConnues[cle];
    if(connue && notifs.some(x => x.id === connue)) continue;
    const alreadyNotified = notifs.find(x => x.op === cle);
    if(alreadyNotified){
      opsConnues[cle] = alreadyNotified.id;
      updateNotif(alreadyNotified, 'running', (op.label || L('ui.operation')) + L('ui.en-cours'));
      continue;
    }
    // New TO OUR EYES: we show it, toast included -- that is the point, every page is
    // told.
    const n = addNotif(op.label || L('ui.operation'), 'running', (op.label || L('ui.operation')) + L('ui.en-cours'));
    n.op = cle;
    opsConnues[cle] = n.id;
  }

  // What has disappeared from the list of running operations has ended: we give it its
  // result, if it is known.
  for(const cle of Object.keys(opsConnues)){
    if(enCours.has(cle)) continue;
    const id = opsConnues[cle];
    const n = notifs.find(x => x.id === id);
    delete opsConnues[cle];
    // The card stops being busy EVEN if its notification was lost in the meantime: the
    // stripe must not depend on an interface object.
    const moduleFini = cle.split('|')[0];
    clearCardBusy(moduleFini);

    // AND IT RELOADS. The end of an operation switched the stripe off and updated the
    // notification, but NEVER asked for the data again: the card kept the previous
    // figures. After a deployment it still announced "34 commits to add" and reopened its
    // button -- reported on 28/08.
    //
    // "fresh" is indispensable: without it the probe answers from its cache, that is to
    // say the very state we have just changed.
    //
    // The case that hid the fault: some operations RESTART THE SERVER (a deployment, an
    // update). During that time the page receives nothing; it learns of the end on the
    // first exchange that gets through again. So it is here, and not in the action's
    // answer, that the reload must happen.
    if(moduleFini){ refreshCard(moduleFini, null, true); }
    if(!n) continue;
    const res = (uiState.results || []).find(r => operationKey(r) === cle);
    if(res){
      const ok = Number(res.code) === 0;
      updateNotif(n, ok ? 'done' : 'error',
        ok ? (res.label || L('ui.operation')) + L('ui.terminee') + (res.seconds ? ' en ' + res.seconds + ' s.' : '.')
           : (res.label || L('ui.operation')) + L('ui.echec-code') + res.code + ')' + (res.log ? ' — journal : ' + res.log : ''));
    } else {
      updateNotif(n, 'done', (n.label || L('ui.operation')) + L('ui.terminee-2'));
    }
  }
}

// BACK ONLINE: noticed as soon as any exchange succeeds, whichever it is.
//
// The "Offline" state was only lifted by a FULL refresh. But that now waits for the page
// to be free (drawer closed, rearranging finished): with the drawer open, the cards
// updated and the banner stayed red -- reported on 27/08. Yet the smallest call that
// lands proves that the server answers.
export function markOnline(){
  const gt = document.getElementById('globalTxt');
  if(!gt || gt.textContent !== 'Hors ligne') return;
  gt.textContent = L('ui.connecte');
  gt.style.color = 'var(--ok)';
  if(gt.parentElement) gt.parentElement.title = L('ui.connecte-api-locale-les');
  const gdot = document.querySelector('#global .dot');
  if(gdot) gdot.style.cssText = 'width:9px;height:9px;border-radius:50%;background:var(--ok)';
  const mb = document.getElementById('modebar');
  if(mb){ const isBusy = mb.classList.contains('busy'); mb.className = 'modebar ok' + (isBusy ? ' busy' : ''); mb.title = ''; }
}

export function updateBell(){ const b=document.getElementById('bellCount'); if(!b) return; b.textContent=notifs.length; b.style.display=notifs.length?'inline-flex':'none'; }
export function toggleDrawer(){ const d=document.getElementById('drawer'); const bk=document.getElementById('drawerBack'); const open=d.classList.toggle('open'); if(bk) bk.classList.toggle('show', open); }

export function toggleDetail(btn){
  const t=btn.closest('.frow'); const d=t&&t.querySelector('.field-detail');
  if(!d) return;
  d.classList.toggle('open');
  const k=d.dataset.k;
  if(k){ if(d.classList.contains('open')) openDetails.add(k); else openDetails.delete(k); }
}
// A long detail: its own window. It has the room and the scrolling a card does not have.
// --- The disk tree: ONE LEVEL AT A TIME (D60 revised) ------------------------
// The server returns only the direct children of the folder asked for; we ask again on
// unfolding. A whole tree carried inside the card is a JSON with no size limit, and
// computation for branches nobody will open.
