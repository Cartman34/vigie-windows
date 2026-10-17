// @author Florent HAZARD <f.hazard@sowapps.com>
import { forgetOrder, saveOrder } from './card-order.js';
import { refresh, toast } from './refresh.js';

// ===== MODE REORGANISATION ===================================================
//
// Pourquoi un MODE, et pas une poignee de deplacement : « pas que ca puisse arriver par
// erreur ». Une poignee, meme discrete, se saisit un jour sans le vouloir. Ici, tant
// qu'on n'est pas entre dans le mode, rien n'est saisissable -- et une fois dedans, les
// actions des cartes sont neutralisees : on range, on n'exploite pas.
export let modeReorg = false;
let inputCard = null;

function currentOrder(){
  return [...document.querySelectorAll('.mcol')].map(col =>
    [...col.querySelectorAll('.card')].map(c => c.dataset.module));
}

function entrerReorg(){
  if(modeReorg) return;
  modeReorg = true;
  document.body.classList.add('reorg');
  // Le bandeau est pose A COTE de #app, pas dedans : #app est entierement redessine a
  // chaque rendu, et le bandeau disparaissait en laissant les cartes en pointilles --
  // le mode etait actif sans plus rien pour le dire ni pour en sortir (signale le
  // 27/08 : « fais en sorte que tout vienne et parte ensemble »).
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

// Glisser-deposer natif : pas de bibliotheque, et le clavier reste possible via les
// boutons de la barre. On depose DANS une colonne, avant la carte survolee.
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
      // Insertion AVANT la carte dont on survole la moitie haute : le repere suit le
      // curseur, on voit ou la carte va tomber.
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

// Remplace le DOM d'une carte par son rendu a jour. Renvoie l'element cree (ou null).
