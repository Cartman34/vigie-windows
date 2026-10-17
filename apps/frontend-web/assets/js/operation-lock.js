// @author Florent HAZARD <f.hazard@sowapps.com>
import { lastModules } from './cards.js';
import { esc } from './format.js';

// ===== VERROU PENDANT UNE OPERATION =========================================
//
// Regle posee le 27/08 : « quand une operation est en cours, les autres ne doivent pas
// etre disponibles ». Y compris les lectures : selon ce qui tourne, relire pendant
// qu'on ecrit donne un resultat qui ne veut rien dire -- une carte qui interroge
// l'installation partagee au milieu d'un deploiement, par exemple.
//
// Ce qui reste permis : RAFRAICHIR une carte. C'est ainsi qu'on regarde l'operation
// avancer, et cela ne fait que relire. Tout le reste -- actions de la barre, boutons de
// resolution des lignes -- est suspendu, sur TOUTES les cartes : les operations de Vigie
// (deploiement, mise a jour, installation d'une dependance) touchent la machine entiere,
// pas seulement la carte d'ou elles partent.
export function runningOperation(){
  // UNE CARTE QUI N'EXISTE PLUS NE TIENT PLUS RIEN.
  //
  // Une carte disparue de l'etat -- la carte d'erreur d'une sonde, une fois la sonde
  // reparee -- restait dans la page avec son marqueur « occupee ». Le verrou s'appuyait
  // dessus et desactivait TOUS les boutons de l'interface, sans qu'aucune operation ne
  // tourne (signale le 29/08 : « c'est grise sans raison », 31 boutons bloques).
  //
  // On ne nettoie que si l'on a bien recu un etat : quand le serveur ne repond pas,
  // lastModules est vide et l'occupation en cours reste vraie.
  if((lastModules||[]).length){
    document.querySelectorAll('.card.busy').forEach(c => {
      if(!lastModules.some(x => x.id === c.dataset.module)) c.remove();
    });
  }
  const c = document.querySelector('.card.busy');
  if(!c) return null;
  const t = c.querySelector('.card-titles .name');
  const m = (lastModules || []).find(x => x.id === c.dataset.module);
  // LES RESSOURCES VIENNENT DU SERVEUR quand il les donne : c'est lui qui tient la marque, et elle les porte.
  // La carte ne les porte que si sa sonde les a declarees, ce que presque aucune ne fait.
  const seen = opsByCard[c.dataset.module];
  return { module: c.dataset.module, titre: (seen && seen.label) || (t ? t.textContent : c.dataset.module),
           ressources: (seen && seen.resources) || (m && m.busyResources) || [] };
}
// FIN D'OPERATION : on eteint ce que markCardBusy avait allume.
//
// Le lisere bleu « operation en cours » restait allume apres la fin, alors que plus rien
// ne tournait ; seul un rafraichissement complet le rendait a sa vraie couleur (signale
// le 28/08). La liste des operations dit pourtant exactement quand ca s'arrete.
export function clearCardBusy(moduleId){
  if(!moduleId) return;
  const sel='.card[data-module="'+((window.CSS&&CSS.escape)?CSS.escape(moduleId):moduleId)+'"]';
  const card=document.querySelector(sel);
  const m=(lastModules||[]).find(x=>x.id===moduleId);
  if(m){ m.busy=false; delete m.busyAction; delete m.busyResources; }
  if(card){
    card.classList.remove('busy');
    // Les boutons de la carte redeviennent ce que le rendu dit d'eux : c'est le verrou,
    // juste apres, qui tranche s'ils restent bloques par une AUTRE operation.
    card.querySelectorAll('.act, .fsolve').forEach(b=>{
      if(b.dataset.held) return;          // bloque par le verrou : il s'en occupe
      if(b.classList.contains('denied')) return;   // interdit par les droits (D65)
      b.disabled=false;
      b.classList.remove('busy');
    });
  }
  applyOperationLock();
}

export function applyOperationLock(){
  const op = runningOperation();
  const raison = op
    ? L('ui.une-operation-est-en-2') + op.titre + L('ui.les-autres-actions-reprendront')
    : '';
  // CE QUI CROISE, et seulement cela (D93). « machine » croise tout. Une action sans
  // ressource declaree est inoffensive : elle reste disponible.
  const tenues = op ? (op.ressources || []) : [];
  const croise = b => {
    if(!op) return false;
    // AN OPERATION THAT DECLARES NOTHING HOLDS NOTHING.
    //
    // Everything was blocked in that case, on the grounds that we did not know what it held (27/08). That was true
    // while marks did not carry their resources; they have since 06/10, and the page reads them from /operations.
    // An empty list therefore means what it says: this operation takes nothing.
    //
    // Without this, a watch task -- which takes nothing and comes round every thirty seconds -- would freeze the
    // whole interface while it lasts.
    if(!tenues.length) return false;
    let r = [];
    try{ r = JSON.parse(b.dataset.res || '[]'); }catch(e){ r = []; }
    if(!r.length) return false;
    if(tenues.indexOf('machine') >= 0 || r.indexOf('machine') >= 0) return true;
    return r.some(x => tenues.indexOf(x) >= 0);
  };
  document.querySelectorAll('.act, .fsolve').forEach(b => {
    if(op && croise(b)){
      // On garde en memoire ce qui etait DEJA desactive pour une autre raison (droits
      // refuses, par exemple) : le verrou ne doit pas reactiver un bouton interdit.
      if(!b.dataset.held){
        b.dataset.held = b.disabled ? 'deja' : 'oui';
        b.dataset.titleBefore = b.title || '';
      }
      b.disabled = true;
      // La marque ne va QUE sur ce que le verrou retient lui-meme : un bouton deja
      // refuse par les droits reste un bouton refuse, il ne devient pas une attente.
      if(b.dataset.held === 'oui'){ b.title = raison; b.classList.add('retenu'); }
    } else if(b.dataset.held){
      if(b.dataset.held === 'oui'){ b.disabled = false; b.title = b.dataset.titleBefore || ''; b.classList.remove('retenu'); }
      delete b.dataset.held;
      delete b.dataset.titleBefore;
    }
  });
}

// LES OPERATIONS EN COURS, telles que /operations les donne, rangees par identifiant de carte.
export let opsByCard = {};
export function resetOpsByCard(){ for(const k of Object.keys(opsByCard)) delete opsByCard[k]; }

function sinceWhen(iso){
  const d = new Date(iso);
  if(isNaN(d)) return '';
  const s = Math.max(0, Math.round((Date.now() - d.getTime()) / 1000));
  if(s < 60) return L('ui.operation-depuis-secondes', s);
  if(s < 3600) return L('ui.operation-depuis-minutes', Math.floor(s / 60));
  return L('ui.operation-depuis-heures', Math.floor(s / 3600));
}

// LA NOTE SOUS L'EN-TETE : une ligne, le libelle de l'operation et depuis combien de temps. Elle est posee et
// retiree ici, jamais reconstruite par la carte -- une carte se redessine a chaque mesure, l'operation non.
export function paintOperationNotes(){
  document.querySelectorAll('.card').forEach(card => {
    const op = opsByCard[card.dataset.module];
    let note = card.querySelector('.card-op');
    if(!op){ if(note) note.remove(); return; }
    const text = esc(op.label || op.action || '');
    const since = sinceWhen(op.at);
    if(!note){
      note = document.createElement('div');
      note.className = 'card-op';
      const head = card.querySelector('.card-head');
      if(head && head.parentNode) head.parentNode.insertBefore(note, head.nextSibling);
      else card.insertBefore(note, card.firstChild);
    }
    note.innerHTML = '<span class="vi vi-fw">&#xE008;</span><span>' + text + '</span>'
                   + (since ? '<span class="card-op-since">· ' + esc(since) + '</span>' : '');
  });
}

// « Operation en cours » sur une carte, sans attendre le serveur : on reutilise l'etat
// `busy` que le contrat porte deja (liseré animé, boutons neutralises), on n'invente pas
// un statut de plus.
export function markCardBusy(moduleId, quoi){
  if(!moduleId) return;
  const sel='.card[data-module="'+((window.CSS&&CSS.escape)?CSS.escape(moduleId):moduleId)+'"]';
  const card=document.querySelector(sel);
  if(!card) return;
  card.classList.add('busy');
  card.querySelectorAll('.actions button').forEach(b=>{ b.disabled=true; });
  const m=(lastModules||[]).find(x=>x.id===moduleId);
  if(m){ m.busy=true; }
  applyOperationLock();
}

// Le corps d'une confirmation : ce que ca FAIT, ce que ca CHANGE, QUAND s'en servir,
// et comment REVENIR EN ARRIERE. Chaque partie ne s'affiche que si l'action l'a
// declaree -- une confirmation a rallonge de generalites ne vaut pas mieux qu'une
// phrase vague (D91).
export function corpsConfirmation(help, ex){
  ex = ex || {};
  const bloc = (headingText, texte) => texte
    ? '<div class="cf-bloc"><div class="cf-t">'+esc(headingText)+'</div><div class="cf-c">'+esc(texte)+'</div></div>'
    : '';
  // CE QUI PASSE D'UN ETAT A L'AUTRE SE MONTRE, il ne se raconte pas. Deux valeurs et
  // une fleche se lisent d'un coup d'oeil ; la meme chose collee au bout d'une phrase se
  // perd (signale le 29/08 sur « De v0.1.25 vers v0.1.25+1 »).
  const t = ex.transition;
  const note = n => n ? '<div class="cf-vn">'+esc(n)+'</div>' : '';
  const blocTransition = (t && (t.from || t.to))
    ? '<div class="cf-bloc"><div class="cf-t">'+esc(L('ui.ce-qui-change-de-version'))+'</div>'
      + '<div class="cf-trans">'
      + '<div class="cf-v">'+esc(t.from||'—')+note(t.fromNote)+'</div>'
      + '<div class="cf-fl">\u2192</div>'
      + '<div class="cf-v cf-v-to">'+esc(t.to||'—')+note(t.toNote)+'</div>'
      + '</div></div>'
    : '';
  // LE DEROULE, EN ETAPES. Combien il y en a, et laquelle finit le travail : c'est ce
  // qu'on veut savoir avant de lancer quelque chose qui dure. La derniere est l'etat
  // d'arrivee, pas une phase -- elle se distingue.
  const etapes = (ex.steps || []);
  const blocEtapes = etapes.length
    ? '<div class="cf-bloc"><div class="cf-t">'+esc(L('ui.ce-qui-va-se-passer'))+'</div>'
      + '<div class="cf-flow">'
      + etapes.map((e, i) => {
          const fin = (i === etapes.length - 1);
          return '<div class="cf-step'+(fin?' cf-step-fin':'')+'">'
               + '<span class="cf-dot">'+(fin?'\u2713':(i+1))+'</span>'
               + '<span class="cf-lbl">'+esc(e)+'</span></div>';
        }).join('<span class="cf-sep">\u2192</span>')
      + '</div></div>'
    : '';
  return blocTransition
       + blocEtapes
       + bloc(L('ui.ce-que-ca-fait'), help)
       + bloc(L('ui.ce-que-ca-change'), ex.impact)
       + bloc(L('ui.quand-en-servir'), ex.usage)
       + bloc(L('ui.revenir-en-arriere'), ex.reversible);
}
