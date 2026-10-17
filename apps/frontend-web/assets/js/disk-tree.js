// @author Florent HAZARD <f.hazard@sowapps.com>
import { doAction } from './actions.js';
import { API, TOKEN } from './api.js';
import { HDS } from './dialog.js';
import { esc } from './format.js';
import { toast } from './refresh.js';

const TREE_CACHE = {};
async function treeNiveau(chemin){
  if(TREE_CACHE[chemin]) return TREE_CACHE[chemin];
  const u = API + '/disk/tree' + (chemin ? ('?path=' + encodeURIComponent(chemin)) : '');
  const r = await fetch(u, {headers:{Authorization:'Bearer '+TOKEN}});
  if(!r.ok){ const j = await r.json().catch(()=>({})); throw new Error(j.error || ('HTTP '+r.status)); }
  const j = await r.json();
  TREE_CACHE[chemin||''] = j;
  return j;
}
function treeRowHtml(e){
  const button = '<button class="tree-open" data-path="'+esc(e.path).replace(/"/g,'&quot;')+'" title="Ouvrir ce dossier dans l\u2019explorateur Windows">\u2197</button>';
  const entete = '<span class="tree-n">'+esc(e.n)+'</span>'
    + '<span class="tree-s">'+esc(e.size||'')+'</span>'
    + '<span class="tree-p">'+esc(String(e.pct==null?'':e.pct))+' %</span>'
    + button;
  return '<details class="tree-node" data-path="'+esc(e.path).replace(/"/g,'&quot;')+'">'
    + '<summary>'+entete+'</summary>'
    + '<div class="tree-kids"><div class="tree-attente">\u2026</div></div></details>';
}
function treeCorpsHtml(niveau){
  const enfants = (niveau.children||[]);
  const fileList = (niveau.files||[]);
  let html = enfants.map(treeRowHtml).join('');
  if(niveau.others && niveau.others.c){
    html += '<div class="tree-leaf tree-mut">'+niveau.others.c+' autres dossiers<span class="tree-s">'+esc(niveau.others.size)+'</span></div>';
  }
  html += fileList.map(f=>'<div class="tree-leaf tree-file">'+esc(f.n)+'<span class="tree-s">'+esc(f.size||'')+'</span></div>').join('');
  if(!html) html = '<div class="tree-leaf tree-mut">Ce dossier ne contient rien de mesurable.</div>';
  return html;
}
// A folder is fetched on its FIRST opening only; after that it is cached.
function treeBrancher(racineEl){
  racineEl.querySelectorAll('details.tree-node').forEach(d=>{
    if(d.dataset.pret) return;
    d.dataset.pret = '1';
    d.addEventListener('toggle', async ()=>{
      if(!d.open || d.dataset.charge) return;
      d.dataset.charge = '1';
      const zone = d.querySelector('.tree-kids');
      try{
        const niveau = await treeNiveau(d.dataset.path);
        zone.innerHTML = treeCorpsHtml(niveau);
        treeBrancher(zone);
        treeBrancherOuvrir(zone);
      }catch(e){
        d.dataset.charge = '';
        zone.innerHTML = '<div class="tree-leaf tree-mut">Lecture impossible : '+esc(e.message||String(e))+'</div>';
      }
    });
  });
}
function treeBrancherOuvrir(zone){
  zone.querySelectorAll('.tree-open').forEach(b=>{
    if(b.dataset.pret) return;
    b.dataset.pret = '1';
    b.onclick = async ev=>{
      ev.preventDefault(); ev.stopPropagation();
      try{ await doAction('open-scan-folder', 'storage', false, L('ui.ouvrir-le-dossier'), '', b, { path: b.dataset.path }, 'manual', false); }
      catch(e){ toast(L('ui.ouverture-impossible')+(e.message||e)); }
    };
  });
}
export async function ouvrirArborescence(){
  HDS.open({ title:L('ui.arborescence-du-disque'), variant:'info',
             html:'<div class="hds-loading"><span class="spin"></span> Lecture du premier niveau\u2026</div>' });
  try{
    const niveau = await treeNiveau('');
    const el = document.querySelector('.hds-body') || document.getElementById('hdsBody');
    const html = '<p class="hds-intro">'+esc(niveau.path)+L('ui.u2014-u00e9pliez-un-dossier')
      + 'Chaque niveau est demand\u00e9 au serveur au moment o\u00f9 il s\u2019ouvre.</p>'
      + '<div class="tree-root">'+treeCorpsHtml(niveau)+'</div>';
    if(el){ el.innerHTML = html; treeBrancher(el); treeBrancherOuvrir(el); }
  }catch(e){
    const el = document.querySelector('.hds-body') || document.getElementById('hdsBody');
    if(el) el.innerHTML = '<p class="hds-intro">Lecture impossible : '+esc(e.message||String(e))+'</p>';
  }
}
// THE PROGRESS BLOCK (Field.progress contract). At the top, the item under way: its title, what it is doing, its bar,
// and in plain words if it has stopped progressing or has failed. Below, each item with its state. At the bottom, the total.
