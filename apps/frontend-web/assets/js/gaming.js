// @author Florent HAZARD <f.hazard@sowapps.com>
import { API, TOKEN } from './api.js';
import { HDS } from './dialog.js';
import { att, esc } from './format.js';

function shortSpan(secondes){
  const s = Math.max(0, Number(secondes) || 0);
  if (s >= 3600) { const h = Math.floor(s / 3600); return `${h} h ${String(Math.floor((s % 3600) / 60)).padStart(2,'0')}`; }
  if (s >= 60) { return `${Math.floor(s / 60)} min`; }
  return `${Math.round(s)} s`;
}
function asPercent(inputValue){ return String(inputValue).replace('.', ',') + ' %'; }
function recapHtml(session){
  const jams = session.jams || [];
  const apps = session.apps || [];
  const quand = session.endedAt ? new Date(session.endedAt) : null;
  const quandTxt = quand ? (quand.toDateString() === new Date().toDateString()
      ? `terminée à ${String(quand.getHours()).padStart(2,'0')}:${String(quand.getMinutes()).padStart(2,'0')}`
      : `terminée le ${String(quand.getDate()).padStart(2,'0')}/${String(quand.getMonth()+1).padStart(2,'0')} à ${String(quand.getHours()).padStart(2,'0')}:${String(quand.getMinutes()).padStart(2,'0')}`) : '';
  // WHAT WAS NOT COUNTED IS SAID HERE. Time between two readings counts, but never more than five minutes at a
  // time, so that a computer asleep or restarted in the middle of a game is not counted as played. Without this
  // line the count looked wrong: on 05/10 a game of 2 h 06 showed 1 h 41 and nothing explained the difference.
  const coupures = session.breaks || [];
  const perdu = session.lostSeconds || 0;
  const quandCoupure = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`; };
  const coupureTxt = !perdu ? '' :
    `<p class="hds-intro">Non compté : <b>${esc(shortSpan(perdu))}</b> — ${coupures.length} interruption${coupures.length>1?'s':''} de plus de cinq minutes`
    + (coupures.length ? ' (' + coupures.slice(0,3).map(c=>`${esc(shortSpan(c.seconds))} à ${esc(quandCoupure(c.at))}`).join(', ') + ')' : '')
    + '. Un ordinateur en veille ou redémarré ne compte pas comme du jeu.</p>';
  const intro = `<p class="hds-intro">Partie de <b>${esc(shortSpan(session.seconds))}</b>${quandTxt?', '+esc(quandTxt):''}. Relevé toutes les trente secondes.</p>` + coupureTxt;
  const jamRows = jams.map(j=>{
    const qui = (j.who && j.who.length)
      ? j.who.map(w=>`${esc(w.label)} ${esc(asPercent(w.share))}`).join(', ')
      : 'la machine elle-même';
    return `<tr><td>${esc(j.label)}</td><td>${esc(shortSpan(j.seconds))}</td><td>${qui}</td></tr>`;
  }).join('');
  const bloc = (headingText, contenu) => `<div class="cf-bloc"><div class="cf-t">${headingText}</div><div class="cf-c">${contenu}</div></div>`;
  const blocJams = jams.length
    ? bloc('Ce qui a gêné la partie', `<table class="hds-table"><thead><tr><th>Bouchon</th><th>Durée</th><th>Qui était en travers</th></tr></thead><tbody>${jamRows}</tbody></table>`)
    : bloc('Ce qui a gêné la partie', 'Rien : la machine a suivi du début à la fin.');
  const firstGame = apps.length ? apps[0] : null;
  const gameBlock = firstGame ? bloc('Le jeu', `Processeur ${esc(asPercent(firstGame.cpu))} en moyenne (pointe ${esc(asPercent(firstGame.cpuMax))}) · Carte graphique ${esc(asPercent(firstGame.gpu))} (pointe ${esc(asPercent(firstGame.gpuMax))}) · Mémoire vive ${esc(String(firstGame.ram).replace('.', ','))} Go`) : '';
  const appRows = apps.map(a=>{
    const shareOfSession = session.seconds ? Math.round(100 * (a.seconds||0) / session.seconds) : 0;
    return `<tr><td>${esc(a.label)}</td><td>${esc(shortSpan(a.seconds))} (${shareOfSession} %)</td><td>${esc(asPercent(a.cpu))}</td><td>${esc(asPercent(a.gpu))}</td><td>${esc(asPercent(a.cpuMax))}</td></tr>`;
  }).join('');
  const blocApps = bloc('Ce que chaque application a pris',
    `<table class="hds-table"><thead><tr><th>Application</th><th>Présente</th><th>CPU moyen</th><th>GPU moyen</th><th>Pointe CPU</th></tr></thead><tbody>${appRows}</tbody></table>`);
  return intro + blocJams + gameBlock + blocApps;
}
async function runGamingAction(type, params){
  const r = await fetch(API+'/actions', { method:'POST',
      headers:{ Authorization:'Bearer '+TOKEN, 'Content-Type':'application/json' },
      body: JSON.stringify(params ? { type, module:'gaming', params } : { type, module:'gaming' }) });
  if(!r.ok) throw new Error('HTTP '+r.status);
  return await r.json();
}
export async function openSessionRecap(startedAt){
  let j;
  try { j = await runGamingAction('game-recap', startedAt ? { session:startedAt } : null); }
  catch(e){ HDS.info('Récapitulatif', 'Vigie n\'a pas répondu : '+e.message, {variant:'warn'}); return; }
  const session = j && j.result && j.result.session;
  if(!session){ HDS.info('Récapitulatif', (j && j.message) || 'Aucune partie gardée.', {variant:'info'}); return; }
  HDS.open({ title:'Récapitulatif — '+session.game, variant:'info', large:true, html:recapHtml(session),
             actions:[{ label:'Parties précédentes', value:'sessions' }, { label:'Fermer', kind:'primary', value:'close', default:true }] })
    .then(v=>{ if(v==='sessions') openPastSessions(); });
}
/* THE PANEL CAN BE ASKED TO OPEN ON SOMETHING (?show=recap).

   The client app opens this window at the end of a game session: it must land on the recap, not on the dashboard
   with the recap one click away. The parameter is read once, then dropped from the address so that a reload does
   not reopen it for ever. */
export function openRequestedView(){
  try {
    const params = new URLSearchParams(location.search);
    const quoi = params.get('show');
    if(!quoi) return;
    params.delete('show');
    const reste = params.toString();
    history.replaceState(null, '', location.pathname + (reste ? '?'+reste : '') + location.hash);
    if(quoi === 'recap') setTimeout(()=>openSessionRecap(), 400);
    if(quoi === 'sessions') setTimeout(()=>openPastSessions(), 400);
  } catch(e) { }
}

export async function openPastSessions(){
  let j;
  try { j = await runGamingAction('game-sessions'); }
  catch(e){ HDS.info('Parties précédentes', 'Vigie n\'a pas répondu : '+e.message, {variant:'warn'}); return; }
  const sessions = (j && j.result && j.result.sessions) || [];
  if(!sessions.length){ HDS.info('Parties précédentes', (j && j.message) || 'Aucune partie gardée.', {variant:'info'}); return; }
  const rows = sessions.map(s=>{
    const d = s.endedAt ? new Date(s.endedAt) : null;
    const dayLabel = d ? (d.toDateString()===new Date().toDateString() ? "Aujourd'hui" : `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')}`) : '';
    const heure = d ? `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}` : '';
    const stub = s.jam ? `${esc(s.jam)} ${esc(shortSpan(s.jamSeconds))}` : 'Aucun bouchon';
    return `<div class="hds-choice-row"><label class="hds-choice">
        <span class="hds-choice-t"><b>${esc(dayLabel)} ${esc(heure)}</b> — ${esc(s.game)}</span>
        <span class="hds-choice-d">${esc(shortSpan(s.seconds))} · ${stub}</span></label>
        <button type="button" class="hds-exclu" data-session="${att(s.startedAt)}">Ouvrir</button></div>`;
  }).join('');
  HDS.open({ title:'Parties précédentes', variant:'info',
             html:`<p class="hds-intro">Les parties gardées, la plus récente en haut. Conservées trente jours.</p><div class="hds-choices">${rows}</div>`,
             actions:[{ label:'Fermer', kind:'primary', value:'close', default:true }] });
  // THE ROW BUTTONS are wired AFTER opening: HDS offers no ready callback, and the body of the window exists as
  // soon as open() has returned.
  const body = document.querySelector('.hds-dialog-body');
  if(body){ body.querySelectorAll('button[data-session]').forEach(b=>{
    b.addEventListener('click', ()=>{ HDS.close(); openSessionRecap(b.dataset.session); }); }); }
}
