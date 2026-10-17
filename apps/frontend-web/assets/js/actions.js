// @author Florent HAZARD <f.hazard@sowapps.com>
import { API, API_MODE, TOKEN } from './api.js';
import { pollCardUntilIdle, refreshCard } from './card-refresh.js';
import { CHOIX_CACHE, itemsDeMaj, listeDeChoix } from './choices.js';
import { HDS, clearBtnBusy, setBtnBusy } from './dialog.js';
import { ouvrirArborescence } from './disk-tree.js';
import { esc } from './format.js';
import { openPastSessions, openSessionRecap } from './gaming.js';
import { addNotif, updateNotif } from './notifications.js';
import { corpsConfirmation, markCardBusy } from './operation-lock.js';
import { opsConnues, syncOperations } from './operations.js';
import { refresh, toast } from './refresh.js';
import { openSettings } from './settings.js';

export async function doAction(type,module,confirmNeeded,label,help,btnEl,params,kind,confirmerDeuxFois,explications){
  const name = label || type;
  // An action may aim at the INTERFACE rather than at the machine: "Manage accounts"
  // simply opens the Settings > Users panel. Nothing to send to the server -- a round
  // trip just to open a screen would be a detour with no purpose.
  if(type==='open-users-settings'){ openSettings('utilisateurs'); return; }
  // Walking the disk tree is an ACTION (the user's choice): it opens its window, which
  // will ask the server for each level as it goes.
  if(type==='disk-tree'){ await ouvrirArborescence(); return; }
  // THE RECAP AND THE LIST OF SESSIONS open their own window: the action only READS what Vigie kept, and the page
  // lays it out. A card would not carry that table (owner, 28/09).
  if(type==='game-recap'){ await openSessionRecap(); return; }
  if(type==='game-sessions'){ await openPastSessions(); return; }
  /* WSL HOGGING THE PORTS: ONE WINDOW, THREE WAYS OUT.

     The Network card offers "Restart WSL" when it is its network host holding the pile of ports -- only it can
     give them back. But stopping WSL is sometimes enough, and doing nothing is a choice too: as long as the
     reserve is not full, nothing breaks. The window says what each one costs and leaves all three, rather than
     asking a closed question whose right answer depends on what is open inside Linux. */
  if(type==='wsl-restart' && !params){
    const choix = await HDS.open({
      title: L('ui.wsl-fenetre-titre'), variant:'warn', cancelValue:null,
      html: '<p>' + esc(L('ui.wsl-fenetre-texte')) + '</p><p>' + esc(L('ui.wsl-fenetre-perte')) + '</p>',
      actions: [
        { label: 'Annuler',                kind:'ghost',  value:null },
        { label: L('ui.wsl-arreter'),    kind:'danger', value:'wsl-shutdown' },
        { label: L('ui.wsl-redemarrer'), kind:'primary', value:'wsl-restart', default:true }
      ]
    });
    if(!choix) return;
    // The choice is ALREADY confirmed by this window: we do not ask again behind it.
    return doAction(choix, module, false, null, null, btnEl, { confirme:true }, 'confirm');
  }
  // A CRITICAL ACTION = a double confirmation. That is the project's standard for any
  // gesture that closes the work under way or touches the whole machine.
  //
  // The two windows do NOT appear in the same place: the first in the middle, the second
  // at the top. Stacked, a quick double click would confirm both without either having
  // been read. Each carries a warning in bold -- amber, then red.
  if(confirmNeeded){
    const ok = await HDS.confirm({
      title: name,
      html: corpsConfirmation(help, explications),
      alerte: confirmerDeuxFois
        ? L('ui.action-critique-elle-affecte')
        : L('ui.cette-action-modifie-votre'),
      alerteNiveau: 'warn',
      confirmLabel: 'Continuer', cancelLabel: 'Annuler'
    });
    if(!ok) return;
    if(confirmerDeuxFois){
      const sur = await HDS.confirm({
        title: name,
        body: L('ui.cette-confirmation-est-la'),
        alerte: L('ui.toutes-vos-applications-vont'),
        alerteNiveau: 'danger',
        placement: 'haut',
        confirmLabel: 'Oui, je confirme', cancelLabel: 'Non, annuler', danger: true
      });
      if(!sur) return;
    }
  }
  // An action of the "choice window" kind: the window opens AT ONCE, with its loader, and
  // only asks the server if its local list has expired. Before, we waited for the answer
  // before opening: the click stayed without visible effect.
  if(kind === 'dialog'){
    let charge = null;
    const choisis = await HDS.choose({
      // Excluding a package FROM the list: it goes into "Ignored packages" of the Tools &
      // packages module, and will not be offered again. This is where one decides it, not
      // in the settings -- the owner asked for that.
      exclure: async id=>{
        const r=await fetch(API+'/parameters',{headers:{Authorization:'Bearer '+TOKEN}});
        if(!r.ok) throw new Error('HTTP '+r.status);
        const j=await r.json();
        const mod=(j.modules||[]).find(m=>m.unit==='tools')||{};
        const pr=(mod.params||[]).find(x=>x.key==='IgnoredPackages')||{};
        const liste=Array.isArray(pr.value)?pr.value.slice():[];
        if(liste.indexOf(id)<0) liste.push(id);
        const w=await fetch(API+'/parameters/tools',{ method:'POST',
          headers:{ Authorization:'Bearer '+TOKEN, 'Content-Type':'application/json' },
          body: JSON.stringify({values:{IgnoredPackages:liste}}) });
        if(!w.ok) throw new Error('HTTP '+w.status);
        toast(id+L('ui.ne-sera-plus-propose'));
      },
      title: name, variant: 'warn', tousCoches: false, confirmLabel: 'Installer',
      charger: async () => {
        charge = await listeDeChoix(type, module);
        const r = charge.result || {};
        const avis = r.verrou
          ? L('ui.le-verrou-du-mode') : "";
        // The server may impose its own wording and FORBID selection (`selection:false`).
        // Without it, every package manager would look able to target one package.
        return { items: itemsDeMaj(charge),
                 tousCoches: (r.preselect === true),
                 verrouille: (r.selection === false),
                 confirmLabel: r.confirmLabel,
                 intro: r.intro || (L('ui.cochez-les-mises-jour')+avis),
                 empty: r.empty || L('ui.aucune-mise-jour-installer') };
      }
    });
    if(!choisis || !choisis.length) return;
    const suite = (charge && charge.result && charge.result.action) || null;
    if(!suite){ addNotif(name,'error',L('ui.reponse-du-serveur-inattendue')); return; }
    delete CHOIX_CACHE[type+'|'+module];   // la liste va changer : ne pas la resservir
    return doAction(suite, module, false, name, help, btnEl, { ids: choisis });
  }

  setBtnBusy(btnEl);
  // The card goes to "operation under way" FROM THE CLICK: waiting for the server's answer
  // left a second where nothing moved, then a card that looked frozen.
  if(module) markCardBusy(module, name);
  const entry=addNotif(name, 'running', L('ui.envoi-de-la-commande'));

  // WE RESERVE THE KEY BEFORE SENDING, NOT AFTER.
  //
  // The operations sync runs every 4 s. If the server takes longer to answer -- and an
  // action that starts a background task often takes several seconds -- it sees the
  // operation BEFORE we have noted its key, does not recognise it, and creates a SECOND
  // notification for the same thing. Seen on 29/08: "Update the installation" and "Vigie
  // update" side by side.
  //
  // Laying the key down now removes the race. If the answer is not asynchronous, we take
  // it away again: nothing is running, there is nothing to recognise.
  const cleAttendue = (module || '') + '|' + type;
  entry.op = cleAttendue;
  opsConnues[cleAttendue] = entry.id;
  if(!API_MODE){ updateNotif(entry,'done','(maquette) POST /actions {type:"'+type+'"}'); clearBtnBusy(btnEl); return; }
  try{
    const r=await fetch(API+"/actions",{ method:"POST",
      headers:{ "Content-Type":"application/json", Authorization:"Bearer "+TOKEN },
      body: JSON.stringify(params ? { type, module, params } : { type, module }) });
    const j=await r.json().catch(()=>({}));
    const okFlag = !j.result || j.result.ok!==false;   // result.ok===false => echec logique meme si HTTP 200
    const st = (r.ok && j.status==='done' && okFlag) ? 'done' : 'error';
    const msg = (j.message || j.status || ('HTTP '+r.status)) + (j.jobId ? ('  [job '+j.jobId+']') : '');
    if(st==='done' && j.result && j.result.async){
      // A non-blocking asynchronous action: the card goes to "under way" and refreshes itself.
      const pollMod = j.result.module || module;
      // The server may aim at a module OTHER than the button's: we then correct the
      // reservation laid down before sending.
      const cleReelle = (pollMod || '') + '|' + type;
      if (cleReelle !== cleAttendue) { delete opsConnues[cleAttendue]; }
      entry.op = cleReelle;
      opsConnues[cleReelle] = entry.id;
      markCardBusy(pollMod, name);
      updateNotif(entry, 'running', j.message || (name+L('ui.en-cours')));
      clearBtnBusy(btnEl);
      // The answer says what is running NOW: we align on it without waiting for the
      // next poll.
      if(j.operations){ syncOperations(j.operations); }
      if(pollMod){ refreshCard(pollMod); pollCardUntilIdle(pollMod, entry, name); }
      return;
    }
    // Nothing is running in the background: the reservation has no reason to exist.
    delete opsConnues[cleAttendue];
    updateNotif(entry, st, msg);
    clearBtnBusy(btnEl);
    if(j.operations){ syncOperations(j.operations); }
    // AN ACTION MAY ANSWER A REPORT (result.detail): a long text, aligned in columns, that a toast would truncate and
    // that the dialog's ordinary body would fold -- it collapses runs of spaces, so every audit and every account
    // listing read crooked. It opens preformatted, in a wide window, and names the file where the report is kept when
    // the action gives one (result.source). Generic on purpose: no action has its own code here.
    if(st==='done' && j.result && j.result.detail){
      const source = j.result.source
        ? '<div class="hds-report-source">' + L('ui.rapport-garde-dans') + esc(String(j.result.source)) + '</div>' : '';
      HDS.open({ title:name, variant:'info', large:true,
                 html:'<pre class="hds-report">' + esc(String(j.result.detail)) + '</pre>' + source });
    }
    // THE END OF THE OPERATION IS THE EVENT, and what follows chains onto it: result plus toast, then a PARTIAL
    // RECOMPUTE of the card, then display. That is GET /modules/:id?fresh=1, the path of the card's own button, and
    // an action that invalidates a card has the right to ask for it (D124, point 2).
    //
    // Before, a 700 ms timer re-read the CACHE. At that instant the server has invalidated the card but has not
    // recomputed it yet: the page therefore showed the OLD value again, until the scheduler came by -- 26 seconds
    // later on the public IP, seen by the owner on 12/10, who had to refresh by hand.
    // A delay is not an event, and there was no need to invent one.
    if(module){ refreshCard(module, null, true); } else { refresh(); }
  }catch(e){ updateNotif(entry,'error','Erreur : '+e.message); clearBtnBusy(btnEl); }
}

// One single place knows REPO_URL: every link marked data-repo-link receives it from here.
// data-repo-link="label" => the text shown is derived from the URL (no duplication).
