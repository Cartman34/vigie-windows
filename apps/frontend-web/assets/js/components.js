// @author Florent HAZARD <f.hazard@sowapps.com>
import { esc } from './format.js';

// ===== COMPOSANTS D'INTERFACE ================================================
// Un seul endroit dessine une bande de titre, une ligne, un interrupteur ou une
// etiquette. Avant, chaque onglet des Parametres reconstruisait ces morceaux a la
// main : la meme chose s'ecrivait de trois facons, et corriger l'alignement d'une
// ligne demandait de retrouver toutes ses copies.
//
// Regle de composition (26/08) : le cadre arrondi appartient au bloc parent. Ces
// composants ne dessinent donc JAMAIS de bordure ni de coin -- ils remplissent.
export const UI = {
  // Bande de titre d'une sous-section, avec son compteur eventuel.
  bande(headingText, compteur){
    return '<div class="um-sub">'+esc(headingText)
      +(compteur!==undefined && compteur!==null && compteur!=='' ? '<span class="um-cpt">'+esc(String(compteur))+'</span>' : '')
      +'</div>';
  },
  // Conteneur de lignes : pleine largeur, sans cadre a lui.
  liste(fieldCount){ return '<div class="um-list">'+(Array.isArray(fieldCount)?fieldCount.join(''):fieldCount)+'</div>'; },
  // UNE ligne : libelle (+ etiquettes) a gauche, commande a droite.
  ligne(o){
    return '<div class="um-card"'+(o.aide?' title="'+esc(o.aide)+'"':'')+'>'
      +'<span>'+esc(o.libelle)+(o.etiquettes||[]).map(t=>UI.etiquette(t)).join('')+'</span>'
      +(o.droite?'<span class="um-param">'+o.droite+'</span>':'')
      +'</div>';
  },
  // Interrupteur : la seule ecriture de ce balisage dans toute l'application.
  interrupteur(attrs, actif){
    return '<span class="swx"><input type="checkbox" '+attrs+(actif?' checked':'')+'><i></i></span>';
  },
  etiquette(t){ return ' <span class="um-tag">'+esc(t)+'</span>'; },
  note(texte){ return '<div class="um-note">'+esc(texte)+'</div>'; },
  // Carte de reglage ISOLEE : un titre, son explication, une commande a droite.
  // C'est le seul cas ou un cadre arrondi est legitime -- elle n'est dans rien.
  carte(o){
    return '<div class="setcard"><div class="setcard-t"><b>'+esc(o.titre)+'</b>'
      +(o.detail?'<small>'+(o.detailHtml?o.detail:esc(o.detail))+'</small>':'')
      +'</div>'+(o.droite||'')+'</div>';
  },
  // Ligne dont le libelle contient deja du balisage (nom + etiquettes + sous-titre).
  ligneHtml(gauche, droite, aide){
    return '<div class="um-card"'+(aide?' title="'+esc(aide)+'"':'')+'>'
      +'<span>'+gauche+'</span>'
      +(droite?'<span class="um-param">'+droite+'</span>':'')+'</div>';
  }
};

// --- Onglet Modules (D48) : activer / couper, cartes du module en rappel ---
