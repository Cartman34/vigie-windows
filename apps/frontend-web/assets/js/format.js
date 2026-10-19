// @author Florent HAZARD <f.hazard@sowapps.com>

export const STATUS_RANK = { neutral:0, ok:0, warn:1, error:2 };
export function esc(s){ return (''+(s==null?'':s)).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
export function att(t){ return esc(t==null?'':t).replace(/"/g,'&quot;'); }

/*
   UNE ACTION, UNE SEULE FACON DE LA DECLARER.

   La meme action se lance depuis deux endroits : le bas de la carte, et le bouton de
   resolution d'un champ. C'etaient deux rendus SEPARES, et ils avaient divergé -- celui
   du champ ne portait ni impact, ni usage, ni reversibilite. Sa confirmation se resumait
   donc a « ce que ca fait », alors que le meme geste, lance de l'autre endroit,
   expliquait tout. Et c'est le chemin le plus visible qui en disait le moins.

   Cette fonction est desormais la SEULE a ecrire les attributs d'une action. Les deux
   boutons different par leur apparence -- classe, libelle, icone -- jamais par ce qu'ils
   declarent. Ajouter un champ a une action le fait apparaitre aux deux endroits, ou a
   aucun : plus de divergence possible.
*/
export function attributsAction(a, moduleId, kind){
  a = a || {};
  return ` data-a="${att(a.id)}" data-m="${att(moduleId)}"`
       + ` data-k="${att(kind)}" data-c="${a.confirm?1:0}" data-c2="${a.confirmTwice?1:0}"`
       + ` data-h="${att(a.help)}"`
       + ` data-imp="${att(a.impact)}" data-usg="${att(a.usage)}" data-rev="${att(a.reversible)}"`
       + ` data-res="${att(JSON.stringify(a.resources||[]))}"`
       + ` data-trn="${att(a.transition?JSON.stringify(a.transition):'')}"`
       + ` data-stp="${att(a.steps?JSON.stringify(a.steps):'')}"`;
}
export function fmt(f){
  if(f.kind==="bool") return f.value?'Oui':'Non';
  if(f.kind==="number") return `${f.value}${f.unit?(' '+f.unit):''}`;
  if(f.kind==="date"){ const d=new Date(f.value);
    return isNaN(d)?(f.value||'—'):d.toLocaleString('fr-FR',{day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'}); }
  return f.value;
}
