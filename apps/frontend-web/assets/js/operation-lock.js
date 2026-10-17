// @author Florent HAZARD <f.hazard@sowapps.com>
import { lastModules } from './cards.js';
import { esc } from './format.js';

// ===== THE LOCK WHILE AN OPERATION RUNS =====================================
//
// Rule set on 27/08: "when an operation is under way, the others must not be available".
// Readings included: depending on what is running, reading while something writes gives a
// result that means nothing -- a card questioning the shared installation in the middle of
// a deployment, for instance.
//
// What stays allowed: REFRESHING a card. That is how one watches the operation move on,
// and it only reads. Everything else -- the bar's actions, the rows' fix buttons -- is
// suspended, on EVERY card: Vigie's operations (a deployment, an update, installing a
// dependency) touch the whole machine, not only the card they started from.
// not only the card they started from.
export function runningOperation(){
  // A CARD THAT NO LONGER EXISTS HOLDS NOTHING ANY MORE.
  //
  // A card gone from the state -- a probe's error card, once the probe was repaired --
  // stayed in the page with its "busy" marker. The lock leaned on it and switched off
  // EVERY button of the interface, with no operation running at all (reported on 29/08:
  // "it is greyed out for no reason", 31 buttons blocked).
  //
  // We only clean up if a state was actually received: when the server does not answer,
  // lastModules is empty and the busy state in force stays true.
  if((lastModules||[]).length){
    document.querySelectorAll('.card.busy').forEach(c => {
      if(!lastModules.some(x => x.id === c.dataset.module)) c.remove();
    });
  }
  const c = document.querySelector('.card.busy');
  if(!c) return null;
  const t = c.querySelector('.card-titles .name');
  const m = (lastModules || []).find(x => x.id === c.dataset.module);
  // THE RESOURCES COME FROM THE SERVER when it gives them: it is the one holding the mark, and the mark carries them.
  // The card only carries them if its probe declared them, which almost none does.
  const seen = opsByCard[c.dataset.module];
  return { module: c.dataset.module, titre: (seen && seen.label) || (t ? t.textContent : c.dataset.module),
           ressources: (seen && seen.resources) || (m && m.busyResources) || [] };
}
// END OF AN OPERATION: we switch off what markCardBusy had switched on.
//
// The blue "operation under way" stripe stayed lit after the end, while nothing was
// running any more; only a full refresh gave it back its true colour (reported on 28/08).
// The list of operations says exactly when it stops, though.
export function clearCardBusy(moduleId){
  if(!moduleId) return;
  const sel='.card[data-module="'+((window.CSS&&CSS.escape)?CSS.escape(moduleId):moduleId)+'"]';
  const card=document.querySelector(sel);
  const m=(lastModules||[]).find(x=>x.id===moduleId);
  if(m){ m.busy=false; delete m.busyAction; delete m.busyResources; }
  if(card){
    card.classList.remove('busy');
    // The card's buttons become again what the rendering says of them: it is the lock,
    // just afterwards, that settles whether they stay blocked by ANOTHER operation.
    card.querySelectorAll('.act, .fsolve').forEach(b=>{
      if(b.dataset.held) return;          // bloque par le verrou : il s'en occupe
      if(b.classList.contains('denied')) return;   // interdit par les droits (D65)
      b.disabled=false;
      b.classList.remove('busy');
    });
  }
  applyOperationLock();
}

export function applyOperationLock(){
  const op = runningOperation();
  const raison = op
    ? L('ui.une-operation-est-en-2') + op.titre + L('ui.les-autres-actions-reprendront')
    : '';
  // WHAT CROSSES, and only that (D93). "machine" crosses everything. An action with no
  // declared resource is harmless: it stays available.
  const tenues = op ? (op.ressources || []) : [];
  const croise = b => {
    if(!op) return false;
    // AN OPERATION THAT DECLARES NOTHING HOLDS NOTHING.
    //
    // Everything was blocked in that case, on the grounds that we did not know what it held (27/08). That was true
    // while marks did not carry their resources; they have since 06/10, and the page reads them from /operations.
    // An empty list therefore means what it says: this operation takes nothing.
    //
    // Without this, a watch task -- which takes nothing and comes round every thirty seconds -- would freeze the
    // whole interface while it lasts.
    if(!tenues.length) return false;
    let r = [];
    try{ r = JSON.parse(b.dataset.res || '[]'); }catch(e){ r = []; }
    if(!r.length) return false;
    if(tenues.indexOf('machine') >= 0 || r.indexOf('machine') >= 0) return true;
    return r.some(x => tenues.indexOf(x) >= 0);
  };
  document.querySelectorAll('.act, .fsolve').forEach(b => {
    if(op && croise(b)){
      // We remember what was ALREADY switched off for another reason (rights refused, for
      // instance): the lock must not bring a forbidden button back to life.
      if(!b.dataset.held){
        b.dataset.held = b.disabled ? 'deja' : 'oui';
        b.dataset.titleBefore = b.title || '';
      }
      b.disabled = true;
      // The mark goes ONLY on what the lock holds back itself: a button already refused by
      // the rights stays a refused button, it does not become a wait.
      if(b.dataset.held === 'oui'){ b.title = raison; b.classList.add('retenu'); }
    } else if(b.dataset.held){
      if(b.dataset.held === 'oui'){ b.disabled = false; b.title = b.dataset.titleBefore || ''; b.classList.remove('retenu'); }
      delete b.dataset.held;
      delete b.dataset.titleBefore;
    }
  });
}

// THE OPERATIONS UNDER WAY, as /operations gives them, arranged by card identifier.
export let opsByCard = {};
export function resetOpsByCard(){ for(const k of Object.keys(opsByCard)) delete opsByCard[k]; }

function sinceWhen(iso){
  const d = new Date(iso);
  if(isNaN(d)) return '';
  const s = Math.max(0, Math.round((Date.now() - d.getTime()) / 1000));
  if(s < 60) return L('ui.operation-depuis-secondes', s);
  if(s < 3600) return L('ui.operation-depuis-minutes', Math.floor(s / 60));
  return L('ui.operation-depuis-heures', Math.floor(s / 3600));
}

// THE NOTE UNDER THE HEADER: one line, the operation's label and for how long. It is laid down and taken away
// here, never rebuilt by the card -- a card redraws itself on every measure, an operation does not.
export function paintOperationNotes(){
  document.querySelectorAll('.card').forEach(card => {
    const op = opsByCard[card.dataset.module];
    let note = card.querySelector('.card-op');
    if(!op){ if(note) note.remove(); return; }
    const text = esc(op.label || op.action || '');
    const since = sinceWhen(op.at);
    if(!note){
      note = document.createElement('div');
      note.className = 'card-op';
      const head = card.querySelector('.card-head');
      if(head && head.parentNode) head.parentNode.insertBefore(note, head.nextSibling);
      else card.insertBefore(note, card.firstChild);
    }
    note.innerHTML = '<span class="vi vi-fw">&#xE008;</span><span>' + text + '</span>'
                   + (since ? '<span class="card-op-since">· ' + esc(since) + '</span>' : '');
  });
}

// "Operation under way" on a card, without waiting for the server: we reuse the `busy`
// state the contract already carries (animated stripe, buttons switched off), we do not
// invent one more status.
export function markCardBusy(moduleId, quoi){
  if(!moduleId) return;
  const sel='.card[data-module="'+((window.CSS&&CSS.escape)?CSS.escape(moduleId):moduleId)+'"]';
  const card=document.querySelector(sel);
  if(!card) return;
  card.classList.add('busy');
  card.querySelectorAll('.actions button').forEach(b=>{ b.disabled=true; });
  const m=(lastModules||[]).find(x=>x.id===moduleId);
  if(m){ m.busy=true; }
  applyOperationLock();
}

// The body of a confirmation: what it DOES, what it CHANGES, WHEN to use it, and how to
// GO BACK. Each part is shown only if the action declared it -- a confirmation padded out
// with generalities is worth no more than
// a vague sentence (D91).
export function corpsConfirmation(help, ex){
  ex = ex || {};
  const bloc = (headingText, texte) => texte
    ? '<div class="cf-bloc"><div class="cf-t">'+esc(headingText)+'</div><div class="cf-c">'+esc(texte)+'</div></div>'
    : '';
  // WHAT GOES FROM ONE STATE TO ANOTHER IS SHOWN, it is not narrated. Two values and an
  // arrow read at a glance; the same thing stuck at the end of a sentence gets lost
  // (reported on 29/08 about "From v0.1.25 to v0.1.25+1").
  const t = ex.transition;
  const note = n => n ? '<div class="cf-vn">'+esc(n)+'</div>' : '';
  const blocTransition = (t && (t.from || t.to))
    ? '<div class="cf-bloc"><div class="cf-t">'+esc(L('ui.ce-qui-change-de-version'))+'</div>'
      + '<div class="cf-trans">'
      + '<div class="cf-v">'+esc(t.from||'—')+note(t.fromNote)+'</div>'
      + '<div class="cf-fl">\u2192</div>'
      + '<div class="cf-v cf-v-to">'+esc(t.to||'—')+note(t.toNote)+'</div>'
      + '</div></div>'
    : '';
  // THE SEQUENCE, IN STEPS. How many there are, and which one finishes the work: that is
  // what one wants to know before starting something long. The last one is the state
  // arrived at, not a phase -- it is set apart.
  const etapes = (ex.steps || []);
  const blocEtapes = etapes.length
    ? '<div class="cf-bloc"><div class="cf-t">'+esc(L('ui.ce-qui-va-se-passer'))+'</div>'
      + '<div class="cf-flow">'
      + etapes.map((e, i) => {
          const fin = (i === etapes.length - 1);
          return '<div class="cf-step'+(fin?' cf-step-fin':'')+'">'
               + '<span class="cf-dot">'+(fin?'\u2713':(i+1))+'</span>'
               + '<span class="cf-lbl">'+esc(e)+'</span></div>';
        }).join('<span class="cf-sep">\u2192</span>')
      + '</div></div>'
    : '';
  return blocTransition
       + blocEtapes
       + bloc(L('ui.ce-que-ca-fait'), help)
       + bloc(L('ui.ce-que-ca-change'), ex.impact)
       + bloc(L('ui.quand-en-servir'), ex.usage)
       + bloc(L('ui.revenir-en-arriere'), ex.reversible);
}
