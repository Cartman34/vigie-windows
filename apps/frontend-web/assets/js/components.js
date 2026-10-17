// @author Florent HAZARD <f.hazard@sowapps.com>
import { esc } from './format.js';

// ===== COMPOSANTS D'INTERFACE ================================================
// One single place draws a title band, a row, a switch or a tag. Before, every Settings tab
// rebuilt those pieces by hand: the same thing was written three ways, and fixing the
// alignment of one row meant finding all of its copies -- and knowing they were all of
// them.
//
// Composition rule (26/08): the rounded frame belongs to the parent block. These components therefore
// NEVER draw a border or a corner -- they fill.
export const UI = {
  // A sub-section's title band, with its count when it has one.
  bande(headingText, compteur){
    return '<div class="um-sub">'+esc(headingText)
      +(compteur!==undefined && compteur!==null && compteur!=='' ? '<span class="um-cpt">'+esc(String(compteur))+'</span>' : '')
      +'</div>';
  },
  // A row container: full width, with no frame of its own.
  liste(fieldCount){ return '<div class="um-list">'+(Array.isArray(fieldCount)?fieldCount.join(''):fieldCount)+'</div>'; },
  // ONE row: label (plus tags) on the left, control on the right.
  ligne(o){
    return '<div class="um-card"'+(o.aide?' title="'+esc(o.aide)+'"':'')+'>'
      +'<span>'+esc(o.libelle)+(o.etiquettes||[]).map(t=>UI.etiquette(t)).join('')+'</span>'
      +(o.droite?'<span class="um-param">'+o.droite+'</span>':'')
      +'</div>';
  },
  // A switch: the only place this markup is written in the whole application.
  interrupteur(attrs, actif){
    return '<span class="swx"><input type="checkbox" '+attrs+(actif?' checked':'')+'><i></i></span>';
  },
  etiquette(t){ return ' <span class="um-tag">'+esc(t)+'</span>'; },
  note(texte){ return '<div class="um-note">'+esc(texte)+'</div>'; },
  // A SETTING ON ITS OWN: a title, its explanation, a control on the right.
  // It is the only case where a rounded frame is legitimate -- it sits inside nothing.
  carte(o){
    return '<div class="setcard"><div class="setcard-t"><b>'+esc(o.titre)+'</b>'
      +(o.detail?'<small>'+(o.detailHtml?o.detail:esc(o.detail))+'</small>':'')
      +'</div>'+(o.droite||'')+'</div>';
  },
  // A row whose label already carries markup (name plus tags plus subtitle).
  ligneHtml(gauche, droite, aide){
    return '<div class="um-card"'+(aide?' title="'+esc(aide)+'"':'')+'>'
      +'<span>'+gauche+'</span>'
      +(droite?'<span class="um-param">'+droite+'</span>':'')+'</div>';
  }
};

// --- Modules tab (D48): switch on or off, the module's cards as a reminder ---
