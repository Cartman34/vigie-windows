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
  // Le libelle du GROUPE vient du catalogue des themes. S'il manque -- la carte a ete
  // rafraichie avant le premier /state --, on garde CELUI QUI EST DEJA AFFICHE plutot
  // que de retomber sur l'identifiant technique : la carte Comptes s'est retrouvee
  // titree « ACCOUNTS » (constate le 27/08).
  const alreadyShown=(card.querySelector('.card-group')||{}).textContent;
  tmp.innerHTML=cardHtmlSafe(m, themeLabels[m.theme]||alreadyShown||m.theme||'');
  const fresh=tmp.firstElementChild;
  // LE GROUPE MASQUE LE RESTE. Le noeud neuf arrive sans le display:none que le filtre
  // avait pose sur l'ancien : une carte d'un groupe decoche revenait donc a l'ecran des
  // qu'elle se rafraichissait seule -- et elles se rafraichissent tout le temps depuis
  // que le serveur calcule en fond (constate le 30/09 sur le groupe Comptes).
  if(hiddenThemes.has(fresh.dataset.theme)) fresh.style.display='none';
  card.replaceWith(fresh);
  wireCardActions(fresh);
  // Le serveur fait foi : si la carte n'est plus occupee, le verrou tombe.
  applyOperationLock();
  const i=(lastModules||[]).findIndex(x=>x.id===m.id);
  if(i>=0) lastModules[i]=m; else lastModules.push(m);
  return fresh;
}
// Recupere l'etat d'un module (live) ou le dernier connu (maquette).
async function fetchModule(moduleId, frais){
  if(API_MODE){
    try{
      // frais : le serveur RECALCULE la carte et attend le resultat. Reserve au bouton
      // de la carte ; le suivi d'une tache de fond, lui, lit le cache.
      const r=await fetch(API+'/modules/'+encodeURIComponent(moduleId)+(frais?'?fresh=1':''),{ headers:{ Authorization:'Bearer '+TOKEN } });
      if(r.ok){ markOnline(); return await r.json(); }
    }catch(e){}
    return null;
  }
  return (lastModules||[]).find(x=>x.id===moduleId)||null;
}
// Rafraichit UNE seule carte (via GET /modules/:id), sans recharger toute la page.
export async function refreshCard(moduleId, btn, frais){
  const sel='.card[data-module="'+((window.CSS&&CSS.escape)?CSS.escape(moduleId):moduleId)+'"]';
  const card=document.querySelector(sel);
  if(!card) return;
  card.classList.add('card-loading');
  const m=await fetchModule(moduleId, frais);
  if(m){ replaceCardDom(m); } else { card.classList.remove('card-loading'); }
}
// Interroge une carte jusqu'a la fin d'une tache de fond (m.busy faux), sans bloquer.
//
// PLAFOND A 1 HEURE, pas 3 minutes. Une mise a jour de paquets prend couramment dix
// minutes ou plus : l'ancien plafond abandonnait en plein travail, la carte restait
// « en cours » et plus rien n'arrivait -- constate sur une mise a jour Chocolatey.
// Le compteur de temps ecoule s'affiche : une operation asynchrone doit se VOIR vivante.
const POLL_MAX_MS = 3600000;
export async function pollCardUntilIdle(moduleId, entry, name){
  const startTs=Date.now();
  let delay=1400;
  const ecoule=()=>{ const s=Math.round((Date.now()-startTs)/1000);
                     return s<60 ? s+' s' : Math.floor(s/60)+' min '+(s%60)+' s'; };
  async function tick(){
    const m=await fetchModule(moduleId);
    if(m) replaceCardDom(m);
    // Une reponse ABSENTE n'est pas une fin : le serveur peut etre en train de recalculer
    // (verrou anti-troupeau) et ne rien renvoyer pour cette carte. L'ancien test prenait
    // ce vide pour un succes et annoncait « termine » aussitot, alors que la tache de fond
    // tournait encore et que la valeur affichee restait « non verifiees ».
    const stillBusy = (!m) || m.busy;
    if(stillBusy && (Date.now()-startTs)<POLL_MAX_MS){
      if(entry) updateNotif(entry,'running', name+' : en cours depuis '+ecoule()+'…');
      delay=Math.min(delay+400, 4000);
      setTimeout(tick, delay);
    } else if(stillBusy){
      // On rend la carte a un etat lisible au lieu de la laisser tourner indefiniment.
      refreshCard(moduleId);
      if(entry) updateNotif(entry,'error', name+L('ui.toujours-en-cours-apres')+ecoule()+L('ui.suivi-abandonne'));
    } else {
      // MEME ENCHAINEMENT A LA FIN D'UNE TACHE DE FOND. Le worker invalide la carte en terminant, donc cette
      // derniere lecture de cache porte encore le rendu d'avant : on recalcule la carte, une seule fois, sur
      // l'evenement « plus occupee ».
      refreshCard(moduleId, null, true);
      if(entry) updateNotif(entry,'done', name+L('ui.termine-en')+ecoule()+'.');
    }
  }
  setTimeout(tick, 900);
}
