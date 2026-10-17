// @author Florent HAZARD <f.hazard@sowapps.com>
import { COL_WIDTH } from './cards.js';

// ===== ORDRE DES CARTES, CHOISI PAR L'UTILISATEUR (D92) ======================
//
// Un ordre est une PREFERENCE : il vit dans le navigateur de ce compte, pas dans la
// configuration de la machine. Un module inconnu (nouveau, ou rallume) n'est pas une
// erreur : il se range simplement a la fin.
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
// L'ordre enregistre est une liste de colonnes, chacune listant des identifiants de
// carte. On ne fait confiance a rien : ce qui n'existe plus est ignore, ce qui est
// nouveau est ajoute a la fin.
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
    // Les nouvelles cartes vont dans la colonne la moins chargee, sans deranger le reste.
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
// Placement retenu des groupes : { nb: nombre de colonnes, col: Map(groupe -> colonne) }.
// Remis a zero quand le nombre de colonnes change (redimensionnement) ou quand
// l'utilisateur reorganise lui-meme ses cartes.
let groupPlacement = null;
export function layoutColumns(masonry){
  // LES CARTES, OU QU'ELLES SOIENT. Apres une premiere repartition, les enfants directs
  // sont les COLONNES : ne regarder que ceux-la ne trouvait plus une seule carte, et un
  // second appel ne faisait rien -- c'est ce qui laissait des colonnes vides quand on
  // decochait un groupe.
  const cardEls = [...masonry.querySelectorAll('.card')];
  if(!cardEls.length) return;
  // UN GROUPE MASQUE NE COMPTE PLUS. Ses cartes restent dans le document, invisibles,
  // mais elles ne prennent plus de place dans le calcul.
  const visibles = cardEls.filter(c => c.style.display !== 'none');
  const dispo = masonry.clientWidth || document.body.clientWidth || 1200;
  const nb = Math.max(1, Math.min(Math.max(visibles.length, 1), Math.floor(dispo / COL_WIDTH)));
  const columnList = [], hauteurs = [];
  for(let i = 0; i < nb; i++){
    const c = document.createElement('div'); c.className = 'mcol';
    columnList.push(c); hauteurs.push(0);
  }
  // UN ORDRE CHOISI PAR L'UTILISATEUR l'emporte sur tout le reste.
  const memo = applyStoredOrder(visibles, nb);
  if(memo){
    memo.forEach((liste, i) => liste.forEach(c => columnList[i].appendChild(c)));
  // LES CARTES MASQUEES RESTENT DANS LE DOCUMENT. « masonry.textContent = '' » efface
  // tout : sans cette ligne, decocher un groupe SUPPRIMAIT ses cartes, et les recocher
  // ne les ramenait qu'au prochain etat recu. Elles vont dans la premiere colonne, en
  // display:none -- invisibles, mais la.
  const caches = cardEls.filter(c => c.style.display === 'none');
  if (caches.length && columnList.length) caches.forEach(c => columnList[0].appendChild(c));
    masonry.textContent = '';
    columnList.forEach(c => masonry.appendChild(c));
    return;
  }

  // PAR GROUPE, et non carte par carte : les trois cartes d'« Outils & paquets » se
  // retrouvaient dans trois colonnes differentes, alors qu'elles se lisent ensemble
  // (signale le 27/08). On pose donc un GROUPE ENTIER dans la colonne la moins
  // remplie ; ses cartes restent contigues, et l'equilibre se fait entre groupes.
  const groups = [];
  const parTheme = new Map();
  for(const cardEl of visibles){
    const g = cardEl.dataset.theme || cardEl.dataset.module || '';
    if(!parTheme.has(g)){ parTheme.set(g, []); groups.push(g); }
    parTheme.get(g).push(cardEl);
  }
  // UNE FOIS POSE, UN GROUPE NE BOUGE PLUS.
  //
  // L'equilibrage se fait sur des hauteurs ESTIMEES : dès qu'une carte grandit -- un
  // champ de plus, un defaut qui s'affiche -- le calcul rendait un autre resultat et les
  // cartes changeaient de colonne sous les yeux de qui les lisait (signale le 28/08).
  // On garde donc le placement precedent tant que la fenetre garde le meme nombre de
  // colonnes et que les memes groupes sont la. Un groupe nouveau, lui, prend la colonne
  // la moins remplie -- et y reste.
  // LE PLACEMENT MEMORISE VAUT POUR UN JEU DE GROUPES DONNE.
  //
  // Il n'etait garde que sur le nombre de colonnes : en decochant un groupe, les autres
  // restaient epingles a leur colonne d'avant et celle qui se vidait le restait -- un
  // trou au milieu de la grille (constate le 01/09, apres le premier correctif qui, lui,
  // ne redistribuait rien du tout).
  //
  // On garde donc aussi QUELS groupes sont affiches. Tant qu'ils ne changent pas, rien ne
  // bouge sous les yeux du lecteur ; des qu'on en masque un, tout se retasse.
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
  // LES CARTES MASQUEES RESTENT DANS LE DOCUMENT. « masonry.textContent = '' » efface
  // tout : sans cette ligne, decocher un groupe SUPPRIMAIT ses cartes, et les recocher
  // ne les ramenait qu'au prochain etat recu. Elles vont dans la premiere colonne, en
  // display:none -- invisibles, mais la.
  const caches = cardEls.filter(c => c.style.display === 'none');
  if (caches.length && columnList.length) caches.forEach(c => columnList[0].appendChild(c));
  masonry.textContent = '';
  columnList.forEach(c => masonry.appendChild(c));
}
// Le nombre de colonnes suit la largeur de la fenetre. On ne refait le partage QUE si
// ce nombre change : redistribuer a chaque pixel ferait danser la page.
let currentColumns = 0;
window.addEventListener('resize', () => {
  const masonry = document.querySelector('.masonry');
  if(!masonry) return;
  const nb = Math.max(1, Math.floor((masonry.clientWidth || 1200) / COL_WIDTH));
  if(nb === currentColumns) return;
  currentColumns = nb;
  // On remet les cartes a plat, puis on repartage.
  const cardEls = [...masonry.querySelectorAll('.card')];
  masonry.textContent = '';
  cardEls.forEach(c => masonry.appendChild(c));
  layoutColumns(masonry);
});
