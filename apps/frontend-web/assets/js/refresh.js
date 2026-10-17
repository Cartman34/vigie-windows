// @author Florent HAZARD <f.hazard@sowapps.com>
import { API, fetchState } from './api.js';
import { renderState } from './cards.js';
import { runningOperation } from './operation-lock.js';
import { hideSplash, pageBusy, progresSplash, setLoading, updateRefreshButton } from './shell.js';

// The last write of the state cache this page has seen: read here, set here, and nowhere else.
let lastStateStamp = '';

export async function refresh(force){
  // Rafraichissement AUTOMATIQUE seulement : une demande explicite n'est jamais differee.
  if(!force){
    const raison = pageBusy();
    if(raison) return;
  }
  // PENDANT UNE OPERATION QUI TIENT LA MACHINE, ON NE RECALCULE PAS.
  //
  // Le recalcul complet refait TOUTES les mesures et dure une minute : demande pendant
  // une mise a jour, il tombe au moment ou le serveur s'arrete. Il ne rend rien, il
  // ajoute de la charge a un geste deja long, et il finit en erreur -- pour une question
  // dont la reponse est de toute facon perimee des que la mise a jour aura fini.
  //
  // On le dit, on ne le fait pas. La relecture automatique, elle, continue : c'est elle
  // qui verra la fin de l'operation.
  const op = runningOperation();
  if(force && op && (op.ressources || []).includes('machine')){
    toast(L('ui.recalcul-pendant-operation') + (op.titre || ''));
    return;
  }
  setLoading(true, !!force);
  // PAS DE PROGRESSION AU DEPART. Annoncer 20 % des que la requete part FIGEAIT l'ecran
  // d'attente : passer en mode « progression connue » coupe l'animation en boucle, et
  // l'aiguille restait plantee tout le temps de la reponse -- une minute entiere quand le
  // serveur redemarre. Tant qu'on ne sait rien, la jauge TOURNE ; elle ne se fige qu'a
  // partir du moment ou elle a une vraie fraction a montrer.
  try{
    const {data,mode}=await fetchState(force);
    if(mode==='live' && data && data.build && window.APP_BUILD && !window.APP_BUILD.includes('__') && data.build!==window.APP_BUILD){ location.reload(); return; }
    progresSplash(0.75);          // etat recu
    renderState(data,mode);
    progresSplash(1);             // panneau affiche
  }
  catch(e){
    // UNE COUPURE ATTENDUE N'EST PAS UNE PANNE. Pendant une mise a jour, le serveur
    // s'arrete : c'est le deroulement du geste demande, pas un incident. On le dit
    // ainsi, en orange, au lieu d'afficher « Hors ligne » en rouge sur ce que
    // l'utilisateur vient lui-meme de declencher.
    const attendu = runningOperation();
    const mb=document.getElementById('modebar'); const busyErr=mb.classList.contains('busy'); mb.className='modebar err'+(busyErr?' busy':''); mb.title=attendu?L('ui.mise-a-jour-en-cours'):L('ui.connexion-api-impossible'); mb.textContent='';
    const msg = (e && e.name==='AbortError') ? L('ui.delai-depasse-le-premier') : (e && e.message ? e.message : e);
    const gt=document.getElementById('globalTxt'); if(gt){ gt.textContent=attendu?L('ui.mise-a-jour-en-cours'):'Hors ligne'; gt.style.color=attendu?'var(--warn)':'var(--err)'; gt.parentElement.title=attendu?L('ui.mise-a-jour-en-cours'):(L('ui.connexion-impossible')+msg); }
    const gdot=document.querySelector('#global .dot'); if(gdot){ gdot.style.cssText='width:9px;height:9px;border-radius:50%;background:'+(attendu?'var(--warn)':'var(--err)'); }
  }
  finally{ setLoading(false); updateRefreshButton(); hideSplash(); }
}
export async function checkVersion(){
  try{
    const r=await fetch(API+'/health'); if(!r.ok) return;
    const j=await r.json();
    // Bouton Atelier : visible UNIQUEMENT si son serveur repond en local (outil de dev).
    const ab=document.getElementById('atelierBtn');
    if(ab){ if(j && j.atelier){ ab.href=j.atelier; ab.hidden=false; } else { ab.hidden=true; } }
    // L'APP SERVEUR A CALCULE QUELQUE CHOSE : on relit le cache, sans attendre notre minute.
    // Elle ne peut pas nous prevenir d'elle-meme -- elle repond, elle n'appelle pas --, mais
    // cette reponse-ci coute trois fois rien et nous passons deja toutes les 15 s. On ne
    // recalcule rien : /state sans « fresh » sert ce qui est deja ecrit (D124).
    if(j && j.stateStamp){
      if(lastStateStamp && j.stateStamp!==lastStateStamp && !runningOperation()){
        lastStateStamp=j.stateStamp; refresh();
      } else { lastStateStamp=j.stateStamp; }
    }
    if(!window.APP_BUILD || window.APP_BUILD.includes('__')) return;
    if(j && j.build && j.build!==window.APP_BUILD){
      // PAS PENDANT UNE OPERATION. Une mise a jour de Vigie sert forcement une nouvelle
      // version : la page se rechargeait donc AU MILIEU de l'operation qui l'avait
      // declenchee. Au retour, le front ne savait plus qu'elle tournait -- boutons
      // reactives, sablier disparu, cartes redistribuees. On attend la fin, et le
      // prochain passage (toutes les 15 s) rechargera.
      if(runningOperation()){ return; }
      location.reload();
    }
  }catch(e){}
}

let dark=true;
export function toggleTheme(){
  // L'icone du footer montre le theme CIBLE : lune quand on est en clair, soleil sinon.
  setTimeout(()=>{ const ic=document.getElementById('themeIc'); if(ic) ic.innerHTML=(dark?'&#xE005;':'&#xE006;'); },0); dark=!dark;
  document.documentElement.setAttribute('data-theme',dark?'':'light');
  const tb=document.getElementById('themeBtn');
  tb.textContent = dark ? '☀' : '☾';
  tb.title = dark ? L('ui.passer-au-theme-clair') : L('ui.passer-au-theme-sombre'); }
// Message bref et autonome, dans la MEME pile que les toasts d’actions (#toastStack).
// L’ancienne version visait un #toast qui n’existe plus : tout appel levait une erreur.
export function toast(msg){
  const stack=document.getElementById('toastStack'); if(!stack) return;
  const el=document.createElement('div'); el.className='toast'; el.textContent=msg;
  stack.appendChild(el); requestAnimationFrame(()=>el.classList.add('show'));
  setTimeout(()=>{ el.classList.remove('show'); setTimeout(()=>el.remove(),220); },3200);
}
