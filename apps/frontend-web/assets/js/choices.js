// @author Florent HAZARD <f.hazard@sowapps.com>
import { API, TOKEN } from './api.js';
import { octets } from './dialog.js';

export const CHOIX_CACHE = {};
const CHOIX_FRAIS_MS = 60000;
async function poster(type, module, params){
  const r = await fetch(API+"/actions", { method:"POST",
    headers:{ "Content-Type":"application/json", Authorization:"Bearer "+TOKEN },
    body: JSON.stringify(params ? { type, module, params } : { type, module }) });
  const j = await r.json().catch(()=>({}));
  return { r, j };
}
export async function listeDeChoix(type, module){
  const cle = type+'|'+module;
  const c = CHOIX_CACHE[cle];
  if(c && (Date.now()-c.at) < CHOIX_FRAIS_MS) return c.j;
  const { j } = await poster(type, module);
  CHOIX_CACHE[cle] = { at: Date.now(), j };
  return j;
}
export function itemsDeMaj(j){
  return (j.result && j.result.updates || []).map(u=>({
    id:u.id,
    // THE MODEL NAMES THE ROW when the server has one: Windows's own title sometimes carries
    // the version instead of the model, and three different devices then read the same.
    title:u.label||u.title,
    // The GROUP and the WEIGHT come from the server: it is the one that saw every spelling
    // of a vendor, and it alone could fold them together (D118).
    group:u.group||'', bytes:u.bytes||0, superseded:!!u.superseded, failure:u.failure||'',
    // Detail already composed by the server (packages), otherwise assembled here (Windows Update).
    detail: u.detail || [u.label?u.title:u.model, u.kb, u.driver?'pilote':null, u.driverDate, u.bytes?octets(u.bytes):null,
            u.downloaded?L('ui.deja-telechargee'):null,
            // Two rows of the same model differ only by their date: we SAY so,
            // instead of leaving the user to compare them digit by digit.
            u.superseded?'version plus ancienne':null,
            // THE LAST ATTEMPT FAILED: say it, rather than re-offering the line as though
            // it had never been tried.
            u.failure?('dernier essai : '+u.failure):null].filter(Boolean).join(' · ')
  }));
}
