// @author Florent HAZARD <f.hazard@sowapps.com>
import { API, TOKEN } from './api.js';
import { lastModules } from './cards.js';
import { UI } from './components.js';
import { toast } from './refresh.js';
import { renderTabApparence, renderTabApropos, renderTabModules, renderTabUtilisateurs } from './settings-tabs.js';

// ===== The application's settings =====
// One menu, four tabs: Notifications, Modules (D48), Appearance, About.
// It replaces the old notifications popup and the old modules drawer.
let settingsTab='notifications';
// The settings drawer's state: open or not, and the module we want to land on.
export let unitsOpen=false, pendingUnitFocus=null;
export function clearPendingUnitFocus(){ pendingUnitFocus=null; }
export function toggleSettings(){
  unitsOpen=!unitsOpen;
  document.getElementById('settingsBack').classList.toggle('show',unitsOpen);
  document.getElementById('settingsDrawer').classList.toggle('open',unitsOpen);
  if(unitsOpen) renderSettings();
}
// Deep link: #parametres, or #parametres/<tab>, opens the menu on load.
export function ouvrirDepuisHash(){
  const h=(location.hash||'').replace(/^#/,'');
  if(!h.startsWith('parametres')) return;
  const parts=h.split('/');
  const onglet=parts[1]||null;
  const targetIndex=parts.length>2?parts[2]:null;
  // #parametres/modules/<module> opens the panel AND unfolds that module.
  setTimeout(()=>{ openSettings(onglet, targetIndex||null); }, 400);
}
window.addEventListener('hashchange', ouvrirDepuisHash);
export function openSettings(tab, unitFocus){
  if(tab) settingsTab=tab;
  pendingUnitFocus=unitFocus||null;
  if(!unitsOpen) toggleSettings(); else renderSettings();
}
export async function renderSettings(){
  const body=document.getElementById('settingsBody');
  const TABS=[['notifications','Notifications','<span class="vi vi-fw">&#xE004;</span>'],['modules','Modules','<span class="vi vi-fw">&#xE002;</span>'],['utilisateurs','Utilisateurs','<span class="vi vi-fw">&#xE00D;</span>'],['apparence','Apparence','<span class="vi vi-fw">&#xE005;</span>'],['apropos','\u00c0 propos','<span class="vi vi-fw">&#xE007;</span>']];
  body.innerHTML='<div class="set-wrap"><nav class="set-nav">'+TABS.map(t=>
    '<button class="set-item'+(settingsTab===t[0]?' on':'')+'" data-tab="'+t[0]+'">'
    +'<span class="set-ic">'+t[2]+'</span>'+t[1]+'</button>').join('')
    +'</nav><div class="set-pane" id="setPane"></div></div>';
  body.querySelectorAll('.set-item').forEach(b=>{ b.onclick=()=>{ settingsTab=b.getAttribute('data-tab'); renderSettings(); }; });
  const pane=document.getElementById('setPane');
  if(settingsTab==='notifications') await renderTabNotifs(pane);
  else if(settingsTab==='modules') await renderTabModules(pane);
  else if(settingsTab==='utilisateurs') await renderTabUtilisateurs(pane);
  else if(settingsTab==='apparence') renderTabApparence(pane);
  else renderTabApropos(pane);
}
export async function getNotifCfg(){
  let cfg={enabled:true,modules:{}};
  try{
    const r=await fetch(API+"/notifications",{headers:{Authorization:"Bearer "+TOKEN}});
    if(r.ok) cfg=await r.json();
  }catch(e){}
  if(!cfg.modules) cfg.modules={};
  return cfg;
}
export async function postNotif(payload){
  const r=await fetch(API+'/notifications',{ method:'POST',
    headers:{ Authorization:'Bearer '+TOKEN, 'Content-Type':'application/json' },
    body: JSON.stringify(payload) });
  if(!r.ok) throw new Error('HTTP '+r.status);
}
// --- Notifications tab: the global switch, plus per-card tuning (D54) ---
async function renderTabNotifs(pane){
  const cfg=await getNotifCfg();
  const on=id=> (id in cfg.modules)? !!cfg.modules[id] : true;
  const mods=(lastModules||[]);
  // How many events does Vigie know how to report? Saying it gives the measure of what
  // the switch commands.
  const total=(cfg.catalog||[]).reduce((t,u)=>t+((u.notifications||[]).length),0);
  pane.innerHTML=
     UI.carte({ titre:L('ui.activer-les-notifications'),
                detail:L('ui.coupe-plus-aucune-bulle'),
                droite: UI.interrupteur('id="ntfGlobal"', cfg.enabled) })
    +UI.bande(L('ui.comment-ca-marche'), total+L('ui.evenements-suivis'))
    +'<ul class="um-points">'
    +'<li>Une bulle apparaît quand un événement <b>survient</b> ou qu’il est <b>résolu</b> — jamais en rappel.</li>'
    +'<li>Elle <b>nomme</b> l’événement : « Température GPU élevée », « Antivirus inactif »…</li>'
    +'<li>Un événement qui demande un administrateur n’est pas signalé à un compte standard, <b>sauf s’il est critique</b> — il l’est alors avec la mention « signalez-le à un administrateur ».</li>'
    +'<li>Le détail se règle dans l’onglet <b>Modules</b>, un interrupteur par événement.</li>'
    +'</ul>';
  pane.querySelector('#ntfGlobal').onchange=async e=>{
    try{ await postNotif({enabled:e.target.checked}); }
    catch(err){ e.target.checked=!e.target.checked; toast(L('ui.reglage-impossible')+(err.message||err)); }
  };
}
