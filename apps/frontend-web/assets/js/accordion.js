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
// DELEGATION, SET ONCE: every accordion added later is covered, including one a window has just built. A
// header that declares an action of its own (an update group, data-act) decides for itself.
function accordionInit(){
  document.addEventListener('click', ev => {
    const head = ev.target.closest && ev.target.closest('.acc > .acc-h');
    if(!head || head.hasAttribute('data-act')) return;
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
  // ON THE BOX, THE TOGGLE WAITS FOR THE END OF THE GESTURE. Cancelling the fold also cancels the ticking the
  // browser had just applied, and it restores it AFTER the handlers: toggling straight away left nothing.
  if(onCheckbox) { queueMicrotask(flip); } else { flip(); }
}

/* WHAT A CARD'S REFRESH DETAIL SAYS (S16, asked for on 30/09).

   Three moments, three different questions, and all three are needed to know what one is dealing with:
     - the page read the cache at such an hour     -- nothing proves the cache itself has moved;
     - the probe produced this measure at such an hour -- that is the age of what is displayed;
     - the scheduler came by at such an hour       -- if it stops coming, the card will stop moving.

   And when the computation fails again and again, it is said with its last error: without that, the card
   serves its last successful value for ever without anyone being able to know. */
