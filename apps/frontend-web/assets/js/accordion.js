// @author Florent HAZARD <f.hazard@sowapps.com>

const ACCORDION_MS = 180;
function accordionAnimate(details){
  const body = details.querySelector(':scope > .acc-b');
  const doux = !window.matchMedia('(prefers-reduced-motion: reduce)').matches && body && body.animate;
  if(!doux){ details.open = !details.open; return; }
  if(details.dataset.accBusy === '1') return;
  const ouvrir = !details.open;
  details.dataset.accBusy = '1';
  details.classList.add('acc--anime');
  if(ouvrir) details.open = true;              // le contenu doit exister pour etre mesure
  const haut = body.scrollHeight;
  const de = ouvrir ? 0 : haut, vers = ouvrir ? haut : 0;
  const anim = body.animate([{ height: de + 'px' }, { height: vers + 'px' }],
                            { duration: ACCORDION_MS, easing: 'ease' });
  anim.onfinish = anim.oncancel = () => {
    details.classList.remove('acc--anime');
    details.dataset.accBusy = '0';
    if(!ouvrir) details.open = false;
  };
}
// LA DELEGATION, posee une fois : tout accordeon ajoute plus tard est pris en charge, y compris celui qu'une
// fenetre vient de construire. Un en-tete qui a son propre gestionnaire (groupe de mises a jour) decide seul.
function accordionInit(){
  document.addEventListener('click', ev => {
    const head = ev.target.closest && ev.target.closest('.acc > .acc-h');
    if(!head || head.hasAttribute('onclick')) return;
    ev.preventDefault();
    accordionAnimate(head.parentElement);
  });
}
accordionInit();

export function onGroupHeadClick(ev, head){
  const cb = head.querySelector('input[data-groupe]');
  if(!cb) return;
  const target = ev.target;
  const onCheckbox = (target === cb);
  const onName = target.closest && target.closest('.hds-grp-n');
  if(!onCheckbox && !onName){          // fleche, vide, compte : le pli, anime par le composant standard
    ev.preventDefault();
    accordionAnimate(head.parentElement);
    return;
  }
  ev.preventDefault();
  const flip = () => { cb.checked = !cb.checked; cb.dispatchEvent(new Event('change', { bubbles:true })); };
  // SUR LA CASE, LA BASCULE ATTEND LA FIN DU GESTE. Annuler le pli annule aussi le cochage que le navigateur
  // venait d'appliquer, et il le retablit APRES les gestionnaires : basculer tout de suite ne laissait rien.
  if(onCheckbox) { queueMicrotask(flip); } else { flip(); }
}

/* LE DETAIL DU RAFRAICHISSEMENT D'UNE CARTE (S16, demande le 30/09).

   Trois moments, trois questions differentes, et il faut les trois pour savoir a quoi on a affaire :
     - la page a lu le cache a telle heure          -- rien ne prouve que le cache, lui, ait bouge ;
     - la sonde a produit cette mesure a telle heure -- c'est l'age de ce qui est affiche ;
     - l'ordonnanceur est passe a telle heure        -- s'il ne passe plus, la carte ne bougera plus.

   Et quand le calcul enchaine les echecs, c'est dit avec sa derniere erreur : sans cela, la carte sert
   indefiniment sa derniere valeur reussie sans que personne puisse le savoir. */
