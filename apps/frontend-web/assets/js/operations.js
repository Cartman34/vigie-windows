// @author Florent HAZARD <f.hazard@sowapps.com>
import { API, API_MODE, TOKEN, openDetails } from './api.js';
import { refreshCard } from './card-refresh.js';
import { lastModules } from './cards.js';
import { addNotif, notifs, updateNotif } from './notifications.js';
import { applyOperationLock, clearCardBusy, opsByCard, paintOperationNotes, resetOpsByCard } from './operation-lock.js';

// ===== LES OPERATIONS SONT PARTAGEES (D95) ===================================
//
// Les notifications vivaient dans la PAGE : une seconde fenetre ne savait rien d'une
// operation lancee depuis la premiere, et une page ouverte APRES le depart d'un
// deploiement n'en voyait aucune trace. Le serveur, lui, sait -- il tient les marqueurs
// d'operation et leurs resultats. Chaque page s'y accorde donc, a intervalle court.
//
// Une notification portee par le serveur est reconnue a sa CLE (module + action) : la
// page qui a lance l'operation garde la sienne, les autres en creent une identique, et
// personne ne se retrouve avec un doublon.
export let opsConnues = {};      // cle -> id de notification locale
export const OPS_MS = 4000;

function operationKey(o){ return (o.module || '') + '|' + (o.action || ''); }

// L'ETAT PEUT VENIR D'AILLEURS QUE DU SONDAGE.
//
// La reponse d'une action le porte deja : s'en servir tout de suite evite d'attendre le
// prochain tour (jusqu'a 4 s) et supprime la course qui creait une seconde notification
// pour la meme operation.
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

  // CE QUE LE SERVEUR DIT DES OPERATIONS EN COURS, garde tel quel et range par carte.
  //
  // La page le reconstituait depuis le DOM, en lisant `busyResources` sur la carte -- que la plupart des cartes ne
  // portent pas. Les ressources arrivaient donc vides, et le repli « on ne sait pas ce qu'elle tient, on bloque
  // tout » s'appliquait : le 06/10, une analyse de disque qui ne retient que le disque eteignait aussi le bouton de
  // Chocolatey. La route /operations, elle, porte le libelle, l'action, les ressources et l'heure de depart.
  resetOpsByCard();
  for(const op of (uiState.running || [])){
    if(op && op.module) opsByCard[op.module] = op;
  }
  // CE QUI EST OCCUPE SE LIT SUR LE VIVANT, JAMAIS SUR UN RENDU (D130). Une carte calculee pendant une operation
  // porte `busy` dans son rendu, et ce rendu est servi jusqu'au recalcul suivant -- un jour pour la carte des
  // paquets. La carte restait grise apres la fin, et il fallait recharger la page. La liste des operations, elle,
  // dit ce qui tourne a l'instant : c'est elle qui pose et retire la classe.
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
    // UNE OPERATION N'A QU'UNE NOTIFICATION, et la suivante REMPLACE la precedente.
    //
    // On ne se fie pas au seul registre des cles : il peut avoir ete vide -- page
    // rechargee, notification effacee a la main -- alors qu'une notification de cette
    // operation existe encore. On cherche donc aussi par la cle PORTEE par la
    // notification. Sans cela, deux annonces de la meme chose se retrouvent cote a cote.
    const connue = opsConnues[cle];
    if(connue && notifs.some(x => x.id === connue)) continue;
    const alreadyNotified = notifs.find(x => x.op === cle);
    if(alreadyNotified){
      opsConnues[cle] = alreadyNotified.id;
      updateNotif(alreadyNotified, 'running', (op.label || L('ui.operation')) + L('ui.en-cours'));
      continue;
    }
    // Nouvelle a NOS yeux : on la montre, toast compris -- c'est le but, toutes les
    // pages sont prevenues.
    const n = addNotif(op.label || L('ui.operation'), 'running', (op.label || L('ui.operation')) + L('ui.en-cours'));
    n.op = cle;
    opsConnues[cle] = n.id;
  }

  // Ce qui a disparu de la liste des operations en cours s'est termine : on lui donne
  // son resultat, s'il est connu.
  for(const cle of Object.keys(opsConnues)){
    if(enCours.has(cle)) continue;
    const id = opsConnues[cle];
    const n = notifs.find(x => x.id === id);
    delete opsConnues[cle];
    // La carte cesse d'etre occupee MEME si sa notification a ete perdue entre-temps :
    // le lisere ne doit pas dependre d'un objet d'interface.
    const moduleFini = cle.split('|')[0];
    clearCardBusy(moduleFini);

    // ET ELLE SE RECHARGE. La fin d'operation eteignait le lisere et mettait a jour la
    // notification, mais ne redemandait JAMAIS les donnees : la carte gardait les
    // chiffres d'avant. Apres un deploiement, elle annoncait encore « 34 commits a
    // ajouter » et rouvrait son bouton -- signale le 28/08.
    //
    // « frais » est indispensable : sans lui la sonde repond depuis son cache, c'est-a-
    // dire l'etat qu'on vient precisement de changer.
    //
    // Le cas qui a masque le defaut : certaines operations RELANCENT LE SERVEUR
    // (deploiement, mise a jour). Pendant ce temps la page ne recoit plus rien ; elle
    // apprend la fin au premier echange qui repasse. C'est donc ici, et pas dans la
    // reponse de l'action, que le rechargement doit se faire.
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

// RETOUR EN LIGNE : le constater des qu'un echange reussit, quel qu'il soit.
//
// L'etat « Hors ligne » n'etait leve que par un rafraichissement COMPLET. Or celui-ci
// attend maintenant que la page soit libre (tiroir ferme, rangement termine) : avec le
// tiroir ouvert, les cartes se mettaient a jour et le bandeau restait rouge -- signale
// le 27/08. Le moindre appel qui aboutit prouve pourtant que le serveur repond.
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
// Detail long : fenetre dediee. Elle a la place et le defilement qu'une carte n'a pas.
// --- Arborescence du disque : UN NIVEAU A LA FOIS (D60 revu) ------------------
// Le serveur ne renvoie que les enfants directs du dossier demande ; on redemande au
// depliage. Un arbre complet embarque dans la carte, c'est un JSON sans limite de taille
// et du calcul pour des branches que personne n'ouvrira.
