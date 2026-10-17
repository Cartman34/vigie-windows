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
    // LE MODELE NOMME LA LIGNE quand le serveur en a un : le titre de Windows porte parfois
    // la version a la place du modele, et trois appareils differents se lisent alors pareil.
    title:u.label||u.title,
    // Le GROUPE et le POIDS viennent du serveur : c'est lui qui a vu toutes les
    // orthographes d'un constructeur, et lui seul pouvait les replier (D118).
    group:u.group||'', bytes:u.bytes||0, superseded:!!u.superseded, failure:u.failure||'',
    // Detail deja compose par le serveur (paquets), sinon assemble ici (Windows Update).
    detail: u.detail || [u.label?u.title:u.model, u.kb, u.driver?'pilote':null, u.driverDate, u.bytes?octets(u.bytes):null,
            u.downloaded?L('ui.deja-telechargee'):null,
            // Deux lignes du meme modele ne se distinguent que par leur date : on le DIT,
            // au lieu de laisser l'utilisateur les comparer chiffre par chiffre.
            u.superseded?'version plus ancienne':null,
            // THE LAST ATTEMPT FAILED: say it, rather than re-offering the line as though
            // it had never been tried.
            u.failure?('dernier essai : '+u.failure):null].filter(Boolean).join(' · ')
  }));
}
