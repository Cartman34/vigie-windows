// @author Florent HAZARD <f.hazard@sowapps.com>
import { REFRESH_MS, SPLASH_MAX_MS, VERSION_POLL_MS } from './config.js';
import { wireDelegation } from './delegate.js';
import { openRequestedView } from './gaming.js';
import { OPS_MS, syncOperations } from './operations.js';
import { checkVersion, refresh } from './refresh.js';
import { ouvrirDepuisHash } from './settings.js';
import { hideSplash, setFootVersion, wireRepoLinks } from './shell.js';

// The one listener that turns what the markup declares into a call (D132, UI-HTML-IN-JS).
wireDelegation();

// ===== Start-up =====
wireRepoLinks();
ouvrirDepuisHash();
openRequestedView();   // ?show=recap: the window the client app opens lands on the recap
setFootVersion();
setTimeout(hideSplash, SPLASH_MAX_MS);   // a guard in case /state never answers
refresh();
setInterval(refresh, REFRESH_MS);
// The operations, on the other hand, are read often and WITHOUT condition: a busy page
// (drawer open, cards being rearranged) must still know what is running elsewhere.
setInterval(syncOperations, OPS_MS);
syncOperations();
checkVersion();
setInterval(checkVersion, VERSION_POLL_MS);
