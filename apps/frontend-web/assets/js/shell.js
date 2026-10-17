// @author Florent HAZARD <f.hazard@sowapps.com>
import { REPO_URL, SPLASH_FADE_MS, SPLASH_MIN_MS } from './config.js';
import { runningOperation } from './operation-lock.js';
import { modeReorg } from './reorder.js';
import { unitsOpen } from './settings.js';

export function wireRepoLinks(){
  const label = REPO_URL.replace(/^https?:\/\//, '');
  document.querySelectorAll('[data-repo-link]').forEach(a=>{
    a.href = REPO_URL;
    a.target = '_blank';          // jamais dans la fenetre --app, qui n'a pas de barre d'adresse
    a.rel = 'noopener';
    if(a.dataset.repoLink === 'label') a.textContent = label;
    if(!a.title) a.title = L('ui.ouvrir-le-depot-du') + label + ')';
  });
}

// Le nom de la machine s'affiche a deux endroits : titre de la barre et sous-titre du splash.
export function setMachineName(host){
  if(!host) return;
  const at = document.getElementById('appTitle');  if(at) at.textContent = host;
  const ss = document.getElementById('splashSub'); if(ss) ss.textContent = host;
  document.title = host + ' — Vigie';
}

export function setFootVersion(){
  const el = document.getElementById('footVersion'); if(!el) return;
  const v = window.APP_VERSION;
  // « version v0.1 » serait redondant : le prefixe porte deja le sens.
  el.textContent = (v && !v.includes('__')) ? v : 'maquette';
}

// Efface l'ecran de chargement, une seule fois, apres une duree minimale d'affichage.
// Appele aussi en cas d'erreur : le message d'erreur doit devenir visible.
// Progression REELLE du chargement, en trois etapes connues. Tant que la progression est
// inconnue, la jauge monte par crans en boucle ; des qu'une etape est franchie, elle
// affiche l'avancement veritable. Le mode « progression connue » existait en CSS sans
// que rien ne l'active : du decor.
export function progresSplash(fraction){
  const el = document.getElementById('splash');
  if(!el || splashDone) return;
  el.classList.add('splash-determine');
  el.style.setProperty('--splash-frac', String(Math.max(0, Math.min(1, fraction))));
}
let splashDone = false;
const splashShownAt = Date.now();
export function hideSplash(){
  if(splashDone) return;
  splashDone = true;
  const el = document.getElementById('splash'); if(!el) return;
  const wait = Math.max(0, SPLASH_MIN_MS - (Date.now() - splashShownAt));
  setTimeout(()=>{
    el.classList.add('splash-off');
    setTimeout(()=>{ el.hidden = true; }, SPLASH_FADE_MS);
  }, wait);
}

// LE BOUTON SUIT L'ETAT DE LA MACHINE. Actif alors qu'il refuserait, il ment ; inerte
// avec sa raison en infobulle, il enseigne.
export function updateRefreshButton(){
  const btn=document.getElementById('btnRefresh');
  if(!btn) return;
  const op = runningOperation();
  const pris = !!(op && (op.ressources || []).includes('machine'));
  if(btn.dataset.titleWas === undefined) btn.dataset.titleWas = btn.title;
  btn.classList.toggle('inerte', pris);
  btn.title = pris ? (L('ui.recalcul-pendant-operation') + (op.titre || '')) : btn.dataset.titleWas;
}
export function setLoading(on, complete){
  const btn=document.getElementById('btnRefresh');
  // Bouton a ICONE SEULE : le libelle vit dans l'infobulle, comme pour les autres boutons
  // d'icone. L'animation de rotation reste, c'est elle qui dit que ca travaille.
  if(btn){ btn.disabled=on; btn.innerHTML = on ? '<span class="spin"></span>' : '↻'; }
  // Le liseré de l'application ET l'en-tete disent tous deux qu'une actualisation a lieu :
  // le premier se voit du coin de l'oeil, le second l'ecrit noir sur blanc.
  const mb=document.getElementById('modebar');
  if(mb) mb.classList.toggle('busy', !!on);
  // SEULEMENT POUR UN VRAI RECALCUL, jamais pour la relecture automatique.
  //
  // Pendant un recalcul complet, les valeurs des cartes sont en sursis : les ternir le dit, et leurs boutons restent
  // cliquables. Mais la page RELIT le cache toutes les minutes, et cette relecture passait par le meme chemin : toute
  // l'interface se ternissait a chaque fois. Signale par le proprietaire le 30/09 -- « ca grise l'interface, c'est
  // trop visible, ca ne devrait pas se voir car il arrive tres frequemment ».
  //
  // Le lisere de l'en-tete continue de dire que quelque chose se passe : discret, il ne coupe pas la lecture.
  document.querySelectorAll('.card').forEach(c => c.classList.toggle('card-loading', !!(on && complete)));
  const meta=document.getElementById('lastRefresh');
  if(meta){
    meta.classList.toggle('busy', !!on);
    if(on){
      if(meta.dataset.textBefore === undefined) meta.dataset.textBefore = meta.textContent;
      // DEUX GESTES, DEUX PHRASES. « Actualisation en cours » disait la meme chose pour
      // une relecture de l'etat -- quelques dixiemes de seconde, servie depuis le cache --
      // et pour un recalcul complet, qui refait toutes les mesures et peut durer une
      // minute. L'attente n'a pas le meme sens, elle ne doit pas avoir le meme texte.
      meta.textContent = complete ? L('ui.recalcul-en-cours') : L('ui.actualisation-en-cours');
    } else {
      // Si le rendu n'a pas eu lieu (erreur reseau), le texte serait reste sur « en cours ».
      if((meta.textContent === L('ui.actualisation-en-cours') || meta.textContent === L('ui.recalcul-en-cours'))
         && meta.dataset.textBefore !== undefined) {
        meta.textContent = meta.dataset.textBefore;
      }
      delete meta.dataset.textBefore;
    }
  }
  // Non bloquant : on garde les cartes existantes pendant l'actualisation.
  // Seulement au TOUT premier chargement (aucune carte), on affiche un repere.
  const app=document.getElementById('app');
  if(on && app && !app.querySelector('.masonry')){
    app.innerHTML='<div class="loading-note"><span class="spin"></span> Chargement du panneau…</div>';
  }
}
// La page est-elle EN TRAIN DE SERVIR ? On ne redessine pas sous les doigts de
// quelqu'un : rangement en cours, fenetre de dialogue ouverte, panneau des reglages
// deploye, ou tiroir des notifications ouvert. Le rafraichissement automatique
// attendra le tour suivant ; une demande EXPLICITE (bouton Actualiser), elle, passe.
export function pageBusy(){
  if(modeReorg) return 'rangement';
  const modale = document.getElementById('hdsBack');
  if(modale && modale.classList.contains('show')) return L('ui.fenetre-ouverte');
  if(typeof unitsOpen !== 'undefined' && unitsOpen) return L('ui.reglages-ouverts');
  const tiroir = document.getElementById('drawer');
  if(tiroir && tiroir.classList.contains('open')) return 'tiroir ouvert';
  return null;
}
