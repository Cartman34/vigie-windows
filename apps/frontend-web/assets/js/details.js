// @author Florent HAZARD <f.hazard@sowapps.com>
import { cardAgeSeconds, fieldsByKey, lastModules, lastStateReadAt, paceLabel } from './cards.js';
import { HDS } from './dialog.js';
import { esc } from './format.js';

function freshnessRow(label, iso, whenNever){
  if (!iso) return `<tr><td>${esc(label)}</td><td>${esc(whenNever || L('ui.jamais'))}</td></tr>`;
  const d = new Date(iso);
  const age = cardAgeSeconds(iso);
  const shown = isNaN(d.getTime()) ? String(iso) : d.toLocaleString();
  return `<tr><td>${esc(label)}</td><td>${esc(shown)} — ${esc(paceLabel(age))}</td></tr>`;
}
export function openFreshness(moduleId){
  const m = (lastModules||[]).find(x => x && x.id === moduleId);
  if (!m) return;
  const f = m.freshness || {};
  const rows =
      freshnessRow(L('ui.fraicheur-lue-par-la-page'), lastStateReadAt)
    + freshnessRow(L('ui.fraicheur-mesure-produite'), f.computedAt, L('ui.fraicheur-jamais-mesuree'))
    + freshnessRow(L('ui.fraicheur-dernier-depart'), f.startedAt, L('ui.fraicheur-aucun-depart'))
    + freshnessRow(L('ui.fraicheur-dernier-passage'), f.refreshedAt, L('ui.fraicheur-aucun-passage'));
  const expected = f.seconds
    ? `<tr><td>${esc(L('ui.fraicheur-intervalle'))}</td><td>${esc(paceLabel(f.seconds))}</td></tr>`
    : `<tr><td>${esc(L('ui.fraicheur-intervalle'))}</td><td>${esc(L('ui.fraicheur-aucun-intervalle'))}</td></tr>`;
  const failed = f.fails
    ? `<div class="hds-report-source">${esc(L('ui.fraicheur-echecs', f.fails))} ${esc(f.lastError || '')}</div>`
    : '';
  HDS.open({ title: m.label, variant: 'info', large: true,
             html: `<table class="hds-table"><tbody>${rows}${expected}</tbody></table>${failed}` });
}

export function ouvrirDetail(key){
  const f=fieldsByKey[key]; if(!f) return;
  if(f.table && f.table.rows && f.table.rows.length){
    const cols=f.table.columns||[];
    const html = '<table class="hds-table"><thead><tr>'
      + cols.map(c=>'<th>'+esc(c)+'</th>').join('')
      + '</tr></thead><tbody>'
      + f.table.rows.map((r,i)=>{
          // Infobulle FACULTATIVE par ligne (contrat : table.tips, parallele a rows) :
          // survoler un nom de processus doit dire d'ou il vient (chemin absolu, editeur,
          // PID). Le title est pose sur la LIGNE : une seule bulle, pas une par cellule
          // qui se disputeraient le survol.
          const tip=(f.table.tips&&f.table.tips[i])?' title="'+esc(String(f.table.tips[i]))+'"':'';
          return '<tr'+tip+'>'+(r||[]).map(v=>'<td>'+esc(v===null||v===undefined?'':String(v))+'</td>').join('')+'</tr>';
        }).join('')
      + '</tbody></table>';
    // A TABLE NEEDS ROOM. 520 px left four columns fighting over the width, the first breaking letter by letter
    // and the last behind a scrollbar. The recap already opened wide for the same reason.
    HDS.open({ title:f.label, html, variant:'info', large:true });
    return;
  }
  HDS.info(f.label, f.guide || f.help || L('ui.aucun-detail-disponible'), {variant:'info'});
}
/* THE RECAP OF A GAME SESSION, ALWAYS IN A POPIN.

   There is too much in it for a card (owner, 28/09): the bottlenecks, the game, then every application. And the same
   window opens through every door -- the card's button, the end of a session, the notification, the list of past
   games -- so that one fact never gets two layouts.

   THE BOTTLENECKS COME FIRST: what got in the way answers the question asked after a session that stuttered. The
   rest explains. */
