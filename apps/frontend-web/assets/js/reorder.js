// @author Florent HAZARD <f.hazard@sowapps.com>
import { forgetOrder, saveOrder } from './card-order.js';
import { refresh, toast } from './refresh.js';

// ===== MODE REORGANISATION ===================================================
//
// Why a MODE, and not a drag handle: "so that it cannot just happen by accident". A handle, however
// discreet, gets grabbed one day without meaning to. Here, as long as one has not entered the mode,
// nothing can be grabbed -- and once inside, the cards' actions are switched off: one is tidying up,
// not operating.
export let modeReorg = false;
let inputCard = null;

function currentOrder(){
  return [...document.querySelectorAll('.mcol')].map(col =>
    [...col.querySelectorAll('.card')].map(c => c.dataset.module));
}

export function entrerReorg(){
  if(modeReorg) return;
  modeReorg = true;
  document.body.classList.add('reorg');
  // The banner is placed NEXT TO #app, not inside it: #app is redrawn entirely on every render, and the
  // banner vanished leaving the cards in dotted outlines -- the mode was active with nothing left to say
  // so, nor to leave it. Reported on 27/08, in these words: "make everything come and go
  // together".
  const app = document.getElementById('app');
  const bar = document.createElement('div');
  bar.className = 'reorg-bar'; bar.id = 'reorgBar';
  bar.innerHTML = '<div><b>Réorganisation</b><br><small>Glisser les cartes. '
                + 'Les actions sont suspendues le temps du rangement.</small></div>'
                + '<div class="sp"><button id="reorgDefaut">Rétablir l’ordre par défaut</button>'
                + '<button class="primaire" id="reorgFin">Terminer</button></div>';
  app.parentElement.insertBefore(bar, app);
  document.getElementById('reorgFin').onclick = () => quitterReorg(true);
  document.getElementById('reorgDefaut').onclick = () => { forgetOrder(); quitterReorg(false); refresh(); };
  armerGlisser();
}

function quitterReorg(garder){
  if(!modeReorg) return;
  if(garder) saveOrder(currentOrder());
  modeReorg = false;
  document.body.classList.remove('reorg');
  const bar = document.getElementById('reorgBar'); if(bar) bar.remove();
  document.querySelectorAll('.card[draggable]').forEach(c => { c.removeAttribute('draggable'); });
  document.querySelectorAll('.mcol.cible').forEach(c => c.classList.remove('cible'));
  if(garder) toast(L('ui.disposition-enregistree'));
}

// Native drag and drop: no library, and the keyboard stays possible through the bar's buttons. One drops
// INTO a column, before the card being hovered.
export function armerGlisser(){
  document.querySelectorAll('.masonry .card').forEach(cardEl => {
    cardEl.setAttribute('draggable', 'true');
    cardEl.ondragstart = e => {
      if(!modeReorg) return false;
      inputCard = cardEl; cardEl.classList.add('drag');
      try{ e.dataTransfer.setData('text/plain', cardEl.dataset.module); }catch(err){}
      e.dataTransfer.effectAllowed = 'move';
    };
    cardEl.ondragend = () => { cardEl.classList.remove('drag'); inputCard = null;
                              document.querySelectorAll('.mcol.cible').forEach(c => c.classList.remove('cible')); };
  });
  document.querySelectorAll('.mcol').forEach(col => {
    col.ondragover = e => {
      if(!modeReorg || !inputCard) return;
      e.preventDefault();
      col.classList.add('cible');
      // Insertion BEFORE the card whose upper half is hovered: the marker follows the cursor, one sees
      // where the card will land.
      const after = [...col.querySelectorAll('.card:not(.drag)')].find(c => {
        const r = c.getBoundingClientRect();
        return e.clientY < r.top + r.height / 2;
      });
      if(after) col.insertBefore(inputCard, after); else col.appendChild(inputCard);
    };
    col.ondragleave = () => col.classList.remove('cible');
    col.ondrop = e => { e.preventDefault(); col.classList.remove('cible'); };
  });
}

// Replaces a card's DOM with its up-to-date rendering. Returns the element created (or null).
