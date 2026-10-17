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
  // Une action peut viser l'INTERFACE et non la machine : « Gerer les comptes » ouvre
  // simplement le panneau Parametres > Utilisateurs. Rien a envoyer au serveur -- lui
  // faire un aller-retour pour ouvrir un ecran serait un detour sans objet.
  if(type==='open-users-settings'){ openSettings('utilisateurs'); return; }
  // L'exploration de l'arborescence est une ACTION (choix utilisateur) : elle ouvre sa
  // fenetre, qui demandera les niveaux au serveur au fur et a mesure.
  if(type==='disk-tree'){ await ouvrirArborescence(); return; }
  // THE RECAP AND THE LIST OF SESSIONS open their own window: the action only READS what Vigie kept, and the page
  // lays it out. A card would not carry that table (owner, 28/09).
  if(type==='game-recap'){ await openSessionRecap(); return; }
  if(type==='game-sessions'){ await openPastSessions(); return; }
  /* WSL QUI ACCAPARE LES PORTS : UNE FENETRE, TROIS ISSUES.

     La carte Reseau propose « Redemarrer WSL » quand c'est son hote reseau qui tient le tas de ports -- lui seul les
     rend. Mais arreter WSL suffit parfois, et ne rien faire est un choix aussi : tant que la reserve n'est pas
     pleine, rien ne casse. La fenetre dit ce que ca coute et laisse les trois, plutot que de poser une question
     fermee a laquelle la bonne reponse depend de ce qu'on a ouvert dans Linux. */
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
    // Le choix est DEJA confirme par cette fenetre : on ne redemande pas derriere.
    return doAction(choix, module, false, null, null, btnEl, { confirme:true }, 'confirm');
  }
  // ACTION CRITIQUE = double confirmation. C'est le standard du projet pour tout geste
  // qui ferme le travail en cours ou touche la machine entiere.
  //
  // Les deux fenetres ne s'affichent PAS au meme endroit : la premiere au centre, la
  // seconde en haut. Superposees, un double clic rapide les validerait toutes les deux
  // sans qu'aucune ait ete lue. Chacune porte une alerte en gras -- orange, puis rouge.
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
  // Action de type « fenetre de choix » : la fenetre s'ouvre TOUT DE SUITE, avec son
  // chargeur, et n'interroge le serveur que si sa liste locale a expire. Auparavant on
  // attendait la reponse avant d'ouvrir : le clic restait sans effet visible.
  if(kind === 'dialog'){
    let charge = null;
    const choisis = await HDS.choose({
      // Exclure un paquet DEPUIS la liste : il part dans « Paquets ignores » du module
      // Outils & paquets, et ne sera plus propose. C'est ici qu'on le decide, pas dans
      // les parametres -- exigence utilisateur.
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
        // Le serveur peut imposer ses textes et INTERDIRE la selection (`selection:false`).
        // Sans cela, tous les gestionnaires auraient l'air de savoir cibler un paquet.
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
  // La carte passe en « operation en cours » DES LE CLIC : attendre la reponse du serveur
  // laissait une seconde ou rien ne bougeait, puis une carte qui semblait figee.
  if(module) markCardBusy(module, name);
  const entry=addNotif(name, 'running', L('ui.envoi-de-la-commande'));

  // ON RESERVE LA CLE AVANT D'ENVOYER, PAS APRES.
  //
  // La synchronisation des operations tourne toutes les 4 s. Si le serveur met plus
  // longtemps a repondre -- et une action qui lance une tache de fond y met souvent
  // plusieurs secondes --, elle voit l'operation AVANT que nous ayons note sa cle, ne la
  // reconnait pas, et cree une SECONDE notification pour la meme chose. Constate le
  // 29/08 : « Mettre a jour l'installation » et « Mise a jour de Vigie » cote a cote.
  //
  // Poser la cle des maintenant supprime la course. Si la reponse n'est pas asynchrone,
  // on la retire : rien ne tourne, il n'y a rien a reconnaitre.
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
      // Action asynchrone non bloquante : la carte passe en "en cours" et s'actualise seule.
      const pollMod = j.result.module || module;
      // Le serveur peut viser un AUTRE module que celui du bouton : on corrige alors
      // la reservation posee avant l'envoi.
      const cleReelle = (pollMod || '') + '|' + type;
      if (cleReelle !== cleAttendue) { delete opsConnues[cleAttendue]; }
      entry.op = cleReelle;
      opsConnues[cleReelle] = entry.id;
      markCardBusy(pollMod, name);
      updateNotif(entry, 'running', j.message || (name+L('ui.en-cours')));
      clearBtnBusy(btnEl);
      // La reponse dit ce qui tourne MAINTENANT : on se cale dessus sans attendre le
      // prochain sondage.
      if(j.operations){ syncOperations(j.operations); }
      if(pollMod){ refreshCard(pollMod); pollCardUntilIdle(pollMod, entry, name); }
      return;
    }
    // Rien ne tourne en fond : la reservation n'a plus lieu d'etre.
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
    // LA FIN DE L'OPERATION EST L'EVENEMENT, et la suite s'enchaine dessus : resultat + toast, puis RECALCUL
    // PARTIEL de la carte, puis affichage. C'est GET /modules/:id?fresh=1, le chemin du bouton de la carte, et une
    // action qui invalide une carte a le droit de le demander (D124, point 2).
    //
    // Avant, un minuteur de 700 ms relisait le CACHE. A cet instant le serveur a invalide la carte mais ne l'a pas
    // encore recalculee : la page reaffichait donc l'ANCIENNE valeur, jusqu'au passage de l'ordonnanceur -- 26
    // secondes plus tard sur l'IP publique, constate par le proprietaire le 12/10, qui a du rafraichir a la main.
    // Un delai n'est pas un evenement, et il n'y avait pas besoin d'en inventer un.
    if(module){ refreshCard(module, null, true); } else { refresh(); }
  }catch(e){ updateNotif(entry,'error','Erreur : '+e.message); clearBtnBusy(btnEl); }
}

// Un seul endroit connait REPO_URL : tous les liens marques data-repo-link la recoivent d'ici.
// data-repo-link="label" => le texte affiche est derive de l'URL (pas de duplication).
