// @author Florent HAZARD <f.hazard@sowapps.com>

// ===== Which mode: the live API, or the mock =====
export const TOKEN = window.API_TOKEN || "";
export const API   = window.API_BASE || "/api/v1";
export const API_MODE = TOKEN && !TOKEN.includes("__");   // jeton reel injecte par le back
export const openDetails = new Set();     // details deplies conserves entre refresh
export const ICONS = {
  immediate:'<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>',
  // confirm = a warning TRIANGLE (validated). The window rectangle shown until then read
  // as an empty box, not as a warning.
  confirm:'<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>',
  manual:'<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M14 3v2h3.59l-9.83 9.83 1.41 1.41L19 6.41V10h2V3h-7zM19 19H5V5h7V3H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7h-2v7z"/></svg>',
  // dialog = a list to TICK: it opens a choice window INSIDE the application. Not to be
  // confused with manual (outgoing arrow = external software), nor with confirm (triangle
  // = a plain yes or no). The three were too close on screen.
  dialog:'<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M3 5h8v2H3V5zm0 6h8v2H3v-2zm0 6h8v2H3v-2zm16.3-9.3l-4.6 4.6-2-2L11.3 12l3.4 3.4 6-6-1.4-1.7z"/></svg>'
};
const KIND_LABEL = { immediate:L('ui.action-immediate'), confirm:L('ui.ouvre-une-fenetre-de'),
                     dialog:L('ui.ouvre-une-fenetre-de-2'), manual:L('ui.ouvre-un-logiciel-externe') };

// Mock inline = ultime repli si ni API ni fichier mock accessibles (file://).
const INLINE_MOCK = {
  generatedAt: new Date().toISOString(),
  themes: [{id:"windows-update",label:"Windows Update"}],
  modules: [{ id:"wu-lock", theme:"windows-update", label:L('ui.verrouillage-des-mises-jour'), status:"warn",
    fields:[{key:"info",label:"Mode",value:L('ui.maquette-aucune-donnee-reelle'),kind:"text"}],
    actions:[] }]
};

function withTimeout(ms){ const c=new AbortController(); const id=setTimeout(()=>c.abort(),ms); return {signal:c.signal,done:()=>clearTimeout(id)}; }
// force = true: the back end is asked to RECOMPUTE the probes instead of serving its cache.
// That is what the "Refresh" button must do -- without it, it handed back control
// instantly and showed the same values again, so it refreshed nothing.
// Loading the page settles for the cache: it has to appear quickly.
export async function fetchState(force){
  if (API_MODE){
    const t=withTimeout(90000);
    try {
      const r = await fetch(API + "/state" + (force ? "?fresh=1" : ""), { headers:{ Authorization:"Bearer "+TOKEN }, signal:t.signal });
      if(!r.ok) throw new Error("API "+r.status);
      return { data: await r.json(), mode:"live" };
    } finally { t.done(); }
  }
  try {
    const r = await fetch("./mock/state.json");
    if(!r.ok) throw new Error();
    return { data: await r.json(), mode:"mock" };
  } catch(e){
    return { data: INLINE_MOCK, mode:"mock" };
  }
}
