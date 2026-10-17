// @author Florent HAZARD <f.hazard@sowapps.com>
import { COL_WIDTH } from './cards.js';

// ===== THE ORDER OF THE CARDS, CHOSEN BY THE USER (D92) ======================
//
// An order is a PREFERENCE: it lives in this account's browser, not in the machine's
// configuration. An unknown module (new, or switched back on) is not an error: it simply
// goes at the end.
const ORDER_KEY = 'vigie.ordreCartes';
let cardOrder = null;
function loadOrder(){
  if(cardOrder) return cardOrder;
  try{ cardOrder = JSON.parse(localStorage.getItem(ORDER_KEY) || 'null'); }catch(e){ cardOrder = null; }
  return cardOrder;
}
export function saveOrder(liste){
  cardOrder = liste;
  try{ localStorage.setItem(ORDER_KEY, JSON.stringify(liste)); }catch(e){}
}
export function forgetOrder(){
  cardOrder = null;
  try{ localStorage.removeItem(ORDER_KEY); }catch(e){}
}
// The stored order is a list of columns, each listing card identifiers. We trust nothing:
// what no longer exists is ignored, what is new is added at the end.
//
function applyStoredOrder(cardEls, nb){
  const memo = loadOrder();
  if(!memo || !Array.isArray(memo)) return null;
  const parId = new Map(cardEls.map(c => [c.dataset.module, c]));
  const columnList = [];
  const places = new Set();
  for(let i = 0; i < nb; i++) columnList.push([]);
  memo.forEach((ids, i) => {
    const targetIndex = Math.min(i, nb - 1);
    (ids || []).forEach(id => {
      const c = parId.get(id);
      if(c && !places.has(id)){ columnList[targetIndex].push(c); places.add(id); }
    });
  });
  const restants = cardEls.filter(c => !places.has(c.dataset.module));
  if(restants.length){
    // New cards go into the least loaded column, without disturbing the rest.
    restants.forEach(c => {
      let k = 0;
      for(let i = 1; i < nb; i++){ if(columnList[i].length < columnList[k].length) k = i; }
      columnList[k].push(c);
    });
  }
  return columnList;
}
function estimatedHeight(cardEl){
  const fieldCount  = cardEl.querySelectorAll('.field').length;
  const buttons = cardEl.querySelectorAll('.actions button').length;
  return 92 + fieldCount * 30 + Math.ceil(buttons / 2) * 34;
}
// The groups' chosen placement: { nb: number of columns, col: Map(group -> column) }.
// Reset when the number of columns changes (a resize) or when the user rearranges their
// own cards.
let groupPlacement = null;
export function layoutColumns(masonry){
  // THE CARDS, WHEREVER THEY ARE. After a first distribution, the direct children are the
  // COLUMNS: looking only at those found not one single card, and a second call did
  // nothing -- which is what left empty columns behind when a group was unticked.
  //
  const cardEls = [...masonry.querySelectorAll('.card')];
  if(!cardEls.length) return;
  // A HIDDEN GROUP NO LONGER COUNTS. Its cards stay in the document, invisible, but they
  // take no more room in the computation.
  const visibles = cardEls.filter(c => c.style.display !== 'none');
  const dispo = masonry.clientWidth || document.body.clientWidth || 1200;
  const nb = Math.max(1, Math.min(Math.max(visibles.length, 1), Math.floor(dispo / COL_WIDTH)));
  const columnList = [], hauteurs = [];
  for(let i = 0; i < nb; i++){
    const c = document.createElement('div'); c.className = 'mcol';
    columnList.push(c); hauteurs.push(0);
  }
  // AN ORDER CHOSEN BY THE USER wins over everything else.
  const memo = applyStoredOrder(visibles, nb);
  if(memo){
    memo.forEach((liste, i) => liste.forEach(c => columnList[i].appendChild(c)));
  // HIDDEN CARDS STAY IN THE DOCUMENT. "masonry.textContent = ''" erases everything:
  // without this line, unticking a group DELETED its cards, and ticking it again only
  // brought them back on the next state received. They go into the first column, in
  // display:none -- invisible, but there.
  const caches = cardEls.filter(c => c.style.display === 'none');
  if (caches.length && columnList.length) caches.forEach(c => columnList[0].appendChild(c));
    masonry.textContent = '';
    columnList.forEach(c => masonry.appendChild(c));
    return;
  }

  // BY GROUP, and not card by card: the three cards of "Tools & packages" ended up in
  // three different columns, while they are read together
  // (reported on 27/08). So a WHOLE GROUP is placed in the least filled column; its cards
  // stay next to each other, and the balance is struck between groups.
  const groups = [];
  const parTheme = new Map();
  for(const cardEl of visibles){
    const g = cardEl.dataset.theme || cardEl.dataset.module || '';
    if(!parTheme.has(g)){ parTheme.set(g, []); groups.push(g); }
    parTheme.get(g).push(cardEl);
  }
  // ONCE PLACED, A GROUP DOES NOT MOVE AGAIN.
  //
  // Balancing works on ESTIMATED heights: as soon as a card grows -- one more field, a
  // fault appearing -- the computation returned another result and the cards changed
  // column under the eyes of whoever was reading them (reported on 28/08).
  // So the previous placement is kept as long as the window keeps the same number of
  // columns and the same groups are there. A new group takes the least filled column --
  // and stays there.
  // THE REMEMBERED PLACEMENT HOLDS FOR A GIVEN SET OF GROUPS.
  //
  // It was kept on the number of columns alone: unticking a group left the others pinned
  // to their former column and the one emptying stayed empty -- a hole in the middle of
  // the grid (seen on 01/09, after the first fix, which redistributed nothing at all).
  //
  //
  // So WHICH groups are shown is kept as well. As long as they do not change, nothing
  // moves under the reader's eyes; as soon as one is hidden, everything packs again.
  const signature = groups.join('|');
  const memePlacement = groupPlacement && groupPlacement.nb === nb && groupPlacement.signature === signature;
  if(!memePlacement) groupPlacement = { nb: nb, signature: signature, col: new Map() };
  for(const g of groups){
    let targetIndex;
    if(groupPlacement.col.has(g)){
      targetIndex = Math.min(groupPlacement.col.get(g), nb - 1);
    } else {
      targetIndex = 0;
      for(let i = 1; i < nb; i++){ if(hauteurs[i] < hauteurs[targetIndex]) targetIndex = i; }
      groupPlacement.col.set(g, targetIndex);
    }
    for(const cardEl of parTheme.get(g)){
      columnList[targetIndex].appendChild(cardEl);
      hauteurs[targetIndex] += estimatedHeight(cardEl);
    }
  }
  // HIDDEN CARDS STAY IN THE DOCUMENT. "masonry.textContent = ''" erases everything:
  // without this line, unticking a group DELETED its cards, and ticking it again only
  // brought them back on the next state received. They go into the first column, in
  // display:none -- invisible, but there.
  const caches = cardEls.filter(c => c.style.display === 'none');
  if (caches.length && columnList.length) caches.forEach(c => columnList[0].appendChild(c));
  masonry.textContent = '';
  columnList.forEach(c => masonry.appendChild(c));
}
// The number of columns follows the window's width. The sharing out is redone ONLY if
// that number changes: redistributing on every pixel would make the page dance.
let currentColumns = 0;
window.addEventListener('resize', () => {
  const masonry = document.querySelector('.masonry');
  if(!masonry) return;
  const nb = Math.max(1, Math.floor((masonry.clientWidth || 1200) / COL_WIDTH));
  if(nb === currentColumns) return;
  currentColumns = nb;
  // The cards are laid flat again, then shared out.
  const cardEls = [...masonry.querySelectorAll('.card')];
  masonry.textContent = '';
  cardEls.forEach(c => masonry.appendChild(c));
  layoutColumns(masonry);
});
