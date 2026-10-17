// @author Florent HAZARD <f.hazard@sowapps.com>
import { onGroupHeadClick } from './accordion.js';
import { refreshCard } from './card-refresh.js';
import { openCardMenu, toggleGroup } from './cards.js';
import { REFRESH_MS, SPLASH_MAX_MS, VERSION_POLL_MS } from './config.js';
import { ouvrirDetail } from './details.js';
import { openRequestedView } from './gaming.js';
import { clearNotifs, deleteNotif, dismissToast } from './notifications.js';
import { OPS_MS, syncOperations, toggleDetail, toggleDrawer } from './operations.js';
import { toggleProgressDone } from './progress.js';
import { checkVersion, refresh, toggleTheme } from './refresh.js';
import { openSettings, ouvrirDepuisHash, toggleSettings } from './settings.js';
import { hideSplash, setFootVersion, wireRepoLinks } from './shell.js';

/*
    THE DOOR, AND THERE IS ONLY ONE.

    A module has no global scope: what it declares exists for itself and for whoever imports it. But markup calls
    functions BY NAME -- onclick="panel.refresh(true)" in the view, and as many again in the HTML the components
    build -- and the browser looks those up on the global object.

    So they are published HERE, all together, under ONE name. Not fifteen globals scattered through fifteen
    files: one door, named, that can be read at a glance and watched. The day the markup goes through delegated
    listeners (UI-HTML-IN-JS), this door closes.
*/
window.panel = {
  clearNotifs, deleteNotif, dismissToast, onGroupHeadClick, openCardMenu, openSettings, ouvrirDetail, refresh, refreshCard, toggleDetail, toggleDrawer, toggleGroup, toggleProgressDone, toggleSettings, toggleTheme
};

// ===== Demarrage =====
wireRepoLinks();
ouvrirDepuisHash();
openRequestedView();   // ?show=recap: the window the client app opens lands on the recap
setFootVersion();
setTimeout(hideSplash, SPLASH_MAX_MS);   // garde-fou si /state ne repond jamais
refresh();
setInterval(refresh, REFRESH_MS);
// The operations, on the other hand, are read often and WITHOUT condition: a busy page
// (drawer open, cards being rearranged) must still know what is running elsewhere.
setInterval(syncOperations, OPS_MS);
syncOperations();
checkVersion();
setInterval(checkVersion, VERSION_POLL_MS);
