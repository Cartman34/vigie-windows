// @author Florent HAZARD <f.hazard@sowapps.com>
import { openCardMenu, toggleGroup } from './cards.js';
import { refreshCard } from './card-refresh.js';
import { onGroupHeadClick } from './accordion.js';
import { ouvrirDetail } from './details.js';
import { clearNotifs, deleteNotif, dismissToast } from './notifications.js';
import { toggleDetail, toggleDrawer } from './operations.js';
import { toggleProgressDone } from './progress.js';
import { refresh, toggleTheme } from './refresh.js';
import { openSettings, toggleSettings } from './settings.js';

/*
    ONE LISTENER FOR THE WHOLE PAGE, AND NO GLOBAL AT ALL (D132, UI-HTML-IN-JS).

    Markup used to call functions by name -- an onclick attribute holding refresh(true) in the view, as much
    again in the HTML the components build -- and a browser looks those names up on the global object, which
    modules do not have. They were published through one door, window.panel; this closes it.

    What the markup carries now is an INTENTION, not a call: data-act="card-refresh" plus the data- attributes
    that name what it acts on. This file is the only place that turns an intention into a function, and it is the
    whole list, readable at a glance.

    Delegation, not one listener per element: the panel rebuilds its cards on every measure, and a listener laid
    on a node that is about to be replaced is a listener lost.
*/
const ACTIONS = {
    'card-refresh':   (el)     => refreshCard(el.dataset.module, el, true),
    'card-menu':      (el, ev) => openCardMenu(ev, el.dataset.module, el.dataset.theme),
    'group-toggle':   (el)     => toggleGroup(el.dataset.theme),
    'group-head':     (el, ev) => onGroupHeadClick(ev, el),
    'detail-open':    (el)     => ouvrirDetail(el.dataset.key),
    'detail-toggle':  (el)     => toggleDetail(el),
    'progress-more':  (el)     => toggleProgressDone(el, el.dataset.key),
    'toast-dismiss':  (el)     => dismissToast(Number(el.dataset.id)),
    'notif-delete':   (el)     => deleteNotif(Number(el.dataset.id)),
    'notifs-clear':   ()       => clearNotifs(),
    'drawer-toggle':  ()       => toggleDrawer(),
    'settings-open':  ()       => openSettings(),
    'settings-toggle': ()      => toggleSettings(),
    'theme-toggle':   ()       => toggleTheme(),
    'refresh-all':    ()       => refresh(true)
};

export function wireDelegation(){
    document.addEventListener('click', ev => {
        const el = ev.target.closest && ev.target.closest('[data-act]');
        if(!el) return;
        const run = ACTIONS[el.dataset.act];
        // AN UNKNOWN INTENTION IS SAID, not swallowed: markup naming an action nobody serves is a button that
        // does nothing, and silence is exactly how that survives a release.
        if(!run){ console.warn('[panel] action inconnue : ' + el.dataset.act); return; }
        run(el, ev);
    });
}
