// @author Florent HAZARD <f.hazard@sowapps.com>
import { API, fetchState } from './api.js';
import { renderState } from './cards.js';
import { runningOperation } from './operation-lock.js';
import { hideSplash, pageBusy, progresSplash, setLoading, updateRefreshButton } from './shell.js';

// The last write of the state cache this page has seen: read here, set here, and nowhere else.
let lastStateStamp = '';

export async function refresh(force){
  // AUTOMATIC refresh only: an explicit request is never deferred.
  if(!force){
    const raison = pageBusy();
    if(raison) return;
  }
  // WHILE AN OPERATION HOLDS THE MACHINE, WE DO NOT RECOMPUTE.
  //
  // A full recompute redoes EVERY measure and takes a minute: asked for during an update,
  // it falls at the very moment the server stops. It returns nothing, it adds load to a
  // gesture that is already long, and it ends in an error -- for a question whose answer
  // is stale anyway as soon as the update has finished.
  //
  // We say it, we do not do it. The automatic re-reading carries on: that is what will
  // see the end of the operation.
  const op = runningOperation();
  if(force && op && (op.ressources || []).includes('machine')){
    toast(L('ui.recalcul-pendant-operation') + (op.titre || ''));
    return;
  }
  setLoading(true, !!force);
  // NO PROGRESS AT THE START. Announcing 20 % as soon as the request leaves FROZE the
  // waiting screen: switching to "known progress" mode stops the looping animation, and
  // the needle stayed planted for the whole of the answer -- a full minute when the
  // server restarts. As long as we know nothing, the gauge TURNS; it only settles once
  // it has a real fraction to show.
  try{
    const {data,mode}=await fetchState(force);
    if(mode==='live' && data && data.build && window.APP_BUILD && !window.APP_BUILD.includes('__') && data.build!==window.APP_BUILD){ location.reload(); return; }
    progresSplash(0.75);          // etat recu
    renderState(data,mode);
    progresSplash(1);             // panneau affiche
  }
  catch(e){
    // AN EXPECTED CUT IS NOT A BREAKDOWN. During an update the server stops: that
    // is the course of the gesture asked for, not an incident. We say it that way,
    // in amber, instead of showing "Offline" in red over something the user has
    // just triggered themselves.
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
    // Atelier button: shown ONLY if its server answers locally (a development tool).
    const ab=document.getElementById('atelierBtn');
    if(ab){ if(j && j.atelier){ ab.href=j.atelier; ab.hidden=false; } else { ab.hidden=true; } }
    // THE SERVER APP HAS COMPUTED SOMETHING: we re-read the cache, without waiting for our minute.
    // It cannot warn us by itself -- it answers, it does not call -- but this particular answer
    // costs next to nothing and we already come by every 15 s. We recompute nothing: /state
    // without "fresh" serves what is already written (D124).
    if(j && j.stateStamp){
      if(lastStateStamp && j.stateStamp!==lastStateStamp && !runningOperation()){
        lastStateStamp=j.stateStamp; refresh();
      } else { lastStateStamp=j.stateStamp; }
    }
    if(!window.APP_BUILD || window.APP_BUILD.includes('__')) return;
    if(j && j.build && j.build!==window.APP_BUILD){
      // NOT DURING AN OPERATION. An update of Vigie necessarily serves a new version: the
      // page therefore reloaded IN THE MIDDLE of the operation that had triggered it. On
      // the way back, the front end no longer knew it was running -- buttons live again,
      // hourglass gone, cards redistributed. We wait for the end, and the next pass (every
      // 15 s) will reload.
      if(runningOperation()){ return; }
      location.reload();
    }
  }catch(e){}
}

let dark=true;
export function toggleTheme(){
  // The footer icon shows the TARGET theme: a moon when we are in light, a sun otherwise.
  setTimeout(()=>{ const ic=document.getElementById('themeIc'); if(ic) ic.innerHTML=(dark?'&#xE005;':'&#xE006;'); },0); dark=!dark;
  document.documentElement.setAttribute('data-theme',dark?'':'light');
  const tb=document.getElementById('themeBtn');
  tb.textContent = dark ? '☀' : '☾';
  tb.title = dark ? L('ui.passer-au-theme-clair') : L('ui.passer-au-theme-sombre'); }
// A brief, self-contained message, in the SAME stack as the action toasts (#toastStack).
// The old version aimed at a #toast that no longer exists: every call raised an error.
export function toast(msg){
  const stack=document.getElementById('toastStack'); if(!stack) return;
  const el=document.createElement('div'); el.className='toast'; el.textContent=msg;
  stack.appendChild(el); requestAnimationFrame(()=>el.classList.add('show'));
  setTimeout(()=>{ el.classList.remove('show'); setTimeout(()=>el.remove(),220); },3200);
}
