// @author Florent HAZARD <f.hazard@sowapps.com>
import { esc } from './format.js';
import { updateBell } from './operations.js';

// ===== Notifications : toasts auto-dismiss + drawer (historique, supprimable) =====
function heure(d){ return d.toLocaleTimeString('fr-FR'); }
export let notifs=[]; let toastEls={}; let nextNotifId=1;
export function addNotif(label, status, message){
  const n={ id:nextNotifId++, label, message, status, ts:new Date() };
  notifs.unshift(n); showToast(n); renderDrawer(); updateBell(); return n;
}
export function updateNotif(n, status, message){
  n.status=status; n.message=message; n.ts=new Date(); showToast(n); renderDrawer();
}
function toastHtml(n){
  return `<span class="t-dot ${n.status}"></span><div class="t-body"><span class="t-label">${esc(n.label)}</span><span class="t-msg">${esc(n.message||'')}</span></div><button class="t-x" title="Fermer" onclick="panel.dismissToast(${n.id})">×</button>`;
}
function showToast(n){
  const stack=document.getElementById('toastStack'); if(!stack) return;
  let rec=toastEls[n.id];
  if(!rec){ const el=document.createElement('div'); el.className='toast'; stack.appendChild(el); rec={el,timer:null}; toastEls[n.id]=rec; requestAnimationFrame(()=>el.classList.add('show')); }
  rec.el.className='toast show '+n.status;
  rec.el.innerHTML=toastHtml(n);
  if(rec.timer){ clearTimeout(rec.timer); rec.timer=null; }
  if(n.status==='done') rec.timer=setTimeout(()=>dismissToast(n.id), 4500);
  else if(n.status==='error') rec.timer=setTimeout(()=>dismissToast(n.id), 9000);
}
export function dismissToast(id){
  const rec=toastEls[id]; if(!rec) return;
  if(rec.timer) clearTimeout(rec.timer);
  rec.el.classList.remove('show');
  setTimeout(()=>{ if(rec.el&&rec.el.parentNode) rec.el.remove(); }, 220);
  delete toastEls[id];
}
// AN OPERATION UNDER WAY IS NOT ERASED (D94). Erasing its notification does not stop it:
// the work carries on in the background, and the only place that said anything about it has
// just been deleted. At the end, that notification is not erased: it is REPLACED by its
// result (succeeded or failed), and that one does erase.
function notifLocked(n){ return n && n.status === 'running'; }

export function deleteNotif(id){
  const n = notifs.find(x => x.id === id);
  if(notifLocked(n)){
    // NO fleeting message: it appeared BEHIND the drawer, for a second and a half -- one may
    // as well say nothing (reported on 27/08). The reason is written at the top of the
    // drawer, permanently for as long as it is true; here we only make the row concerned
    // blink, where the click happened.
    const el = document.querySelector('.dn[data-id="' + id + '"]');
    if(el){ el.classList.remove('refus'); void el.offsetWidth; el.classList.add('refus'); }
    return;
  }
  notifs=notifs.filter(n=>n.id!==id); dismissToast(id); renderDrawer(); updateBell();
}
export function clearNotifs(){
  // "Clear all" honours the lock: what is running stays, the rest goes. Nothing to announce
  // -- the drawer itself shows what is left, and why.
  notifs.filter(n => !notifLocked(n)).forEach(n => dismissToast(n.id));
  notifs = notifs.filter(notifLocked);
  renderDrawer(); updateBell();
}
function renderDrawer(){
  const body=document.getElementById('drawerBody'); if(!body) return;
  if(!notifs.length){ body.innerHTML='<div class="drawer-empty">Aucune notification.</div>'; return; }
  // AT THE TOP OF THE DRAWER: what is running, and why those notifications do not erase.
  // Permanent for as long as it is true, in the very place where one clicks.
  const enCours = notifs.filter(notifLocked).length;
  const entete = enCours
    ? '<div class="dn-note">' + (enCours === 1
        ? L('ui.une-operation-est-en')
        : enCours + L('ui.operations-sont-en-cours'))
      + '</div>'
    : '';
  body.innerHTML = entete + notifs.map(n=>{
    const chip=n.status==='running'?'<span class="spin"></span>En cours':n.status==='done'?L('ui.reussi'):L('ui.echec');
    return `<div class="dn ${n.status}" data-id="${n.id}">
      <div class="dn-head"><span class="t-dot ${n.status}"></span><span class="dn-label">${esc(n.label)}</span>
        ${notifLocked(n)
            // The in-house font has no padlock, and one does not invent a glyph for that:
            // the application's HOURGLASS already says "under way", which is exactly the
            // reason for the lock.
            ? '<span class="dn-lock" title="Opération en cours : sa notification ne peut pas être effacée."><span class="spin"></span></span>'
            : `<button class="dn-del" title="Supprimer" onclick="panel.deleteNotif(${n.id})">×</button>`}</div>
      <div class="dn-msg">${esc(n.message||'')}</div>
      <div class="dn-time">${chip} — ${heure(n.ts)}</div>
    </div>`;
  }).join('');
}
